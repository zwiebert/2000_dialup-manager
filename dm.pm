package dm;
use strict;

BEGIN {
    use Exporter   ();
    use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
    # set the version for version checking
    $VERSION     = 1.5;
    # if using RCS/CVS, this may be preferred
    $VERSION = do { my @r = (q$Revision: 1.3 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r }; # must be all one line, for MakeMaker

    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    %EXPORT_TAGS = ();		# eg: TAG => [ qw!name1 name2! ],

    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK   = qw(@isps $isp_curr $state_startup $db_ready @cfg_labels @cfg_isp $cost_out_file
		      %isp_cfg_map $time_start $curr_secs_per_unit
		      $flag_stop_defer $state $state_startup $state_offline $state_dialing $state_online
		      @commands_on_startup  @commands_before_dialing  @commands_on_connect
		      @commands_on_connect_failure @commands_on_disconnect
		      $cfg_isp $cfg_cmd $cfg_disconnect_cmd $cfg_label $cfg_color $cfg_tarif $cfg_active $cfg_SIZE
		      $ppp_offset);
}
use vars      @EXPORT_OK;

# non-exported package globals go here
use vars      qw();

# initialize package globals, first exported ones

# then the others (which are still accessible as $Some::Module::stuff)

# all file-scoped lexicals must be created before
# the functions below that use them.

# file-private lexicals go here

# make all your functions, whether exported or not;
# remember to put something interesting in the {} stubs


#! /usr/local/bin/perl -w

use strict;
use Time::Local;
use Fcntl;
use Fcntl qw(:flock);
use IO::Handle;

$0 =~ m!^(.*)/([^/]*)$! or die "path of program file required (e.g. ./$0)";
my ($progdir, $progname) = ($1, $2);

use Graphs;
use Dialup_Cost;

@isps=();
%isp_cfg_map=();
($cfg_isp, $cfg_cmd, $cfg_disconnect_cmd, $cfg_label, $cfg_color, $cfg_tarif, $cfg_active, $cfg_SIZE) = (0..20);
my @cfg_att_names = ('id', 'up_cmd', 'down_cmd', 'label', 'color', 'rate', 'active_flag');
my %n2i; foreach my $i (0..$#cfg_att_names) { $n2i{$cfg_att_names[$i]} = $i; }

sub get_isp_tarif ($) { my $cfg=$isp_cfg_map{$_[0]}; $$cfg[$cfg_tarif]; }   # payment-id of ISP
sub get_isp_cmd ($) { my $cfg=$isp_cfg_map{$_[0]}; $$cfg[$cfg_cmd]; }       # external dialup command of ISP
sub get_isp_disconnect_cmd ($) { my $cfg=$isp_cfg_map{$_[0]}; $$cfg[$cfg_disconnect_cmd]; }       # external disconnect command of ISP
sub get_isp_label ($) { my $cfg=$isp_cfg_map{$_[0]}; $$cfg[$cfg_label]; }   # label on connect button of ISP
sub get_isp_color ($) { my $cfg=$isp_cfg_map{$_[0]}; $$cfg[$cfg_color]; }   # color in cost graph of ISP
sub get_isp_flag_active ($) { my $cfg=$isp_cfg_map{$_[0]}; $$cfg[$cfg_active]; }   # string of single letter flags
sub get_isp_cfg ($$) { my $cfg=$isp_cfg_map{$_[0]}; $$cfg[$_[1]]; }         # one of the item of ISP selected by INDEX
sub set_isp_cfg ($) { my ($a)=@_; $isp_cfg_map{$$a[0]} = $a; }              # store/replace CFG by reference

$ppp_offset=30;
my $unit_end_inaccuracy=5; # hangup this seconds before we think a unit ends
$db_ready = 0; # debugging switch
my $db_tracing = defined ($ENV{'DB_TRACING'});
$isp_curr= defined $ARGV[0] ? $ARGV[0] : '';
my $sr_pid;
my $cfg_file="${progdir}/dialup_manager.cfg";
my $cfg_file_usr=$ENV{"HOME"} . "/.dialup_manager.cfg";
my $cost_file="${progdir}/dialup_cost.data";
my $cost_file_usr=$ENV{"HOME"} . "/.dialup_cost.data";
$cost_out_file=$ENV{"HOME"} . "/.dialup_cost.log";
$flag_stop_defer=0;  # if not 0 then stop just before next pay-unit

# constants
my $days_per_week = 7;
my $hours_per_day = 24;
my $mins_per_hour = 60;
my $mins_per_day = $mins_per_hour * $hours_per_day;
my $secs_per_min = 60;
my $secs_per_hour = $secs_per_min * $mins_per_hour;
my $secs_per_day = $secs_per_hour * $hours_per_day;

##--- Protos
 sub db_time ();
 sub db_trace ( $ );
 sub link_started ();
 sub link_stopped ();
 sub tick ();
 sub state_trans_startup_to_offline ();
 sub state_trans_offline_to_dialing ();
 sub state_trans_dialing_to_online ();
 sub state_trans_dialing_to_offline ();
 sub state_trans_online_to_offline ();
 sub update_state ();
 sub get_sum ( $ );
 sub format_ltime ( $ );
 sub parse_ltime ($);
 sub format_day_time ( $ );
 sub parse_day_time ( $ );
 sub write_ulog ();
 sub update_sum ();
 sub start_plog_scanner ();
 sub stop_log_scanner ();
 sub check_automatic_disconnect ();
 sub dialup ( $ );
 sub disconnect ();
 sub escape_string ($);
 sub unescape_string ($);
 sub read_config ($);
 sub write_config ($);
##----

# misc globals
$curr_secs_per_unit=10;
$time_start = 0;
my $time_disconnect = 0;
my $time_dial_start = 0;
my $db_start_time = time ();

# State Transition Command Hooks

@commands_on_startup = ();
@commands_before_dialing = ();
@commands_on_connect = ();
@commands_on_connect_failure = ();
@commands_on_disconnect = ();

# Commands Issued Each Tick
my @commands_while_online = (\&update_sum, \&check_automatic_disconnect);


($state_startup, $state_offline, $state_dialing, $state_online) = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9);
$state=$state_startup;

my %records;
my @template_rate_record = (0, 0);
my ($offs_sum, $offs_time_last) = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9);


sub db_time () {
    time ();
#    (time () - $db_start_time) + timelocal(3, 54, 13, 1, 11, 99);
#    (time () - $db_start_time) + timelocal(3, 55, 17, 1, 11, 99);
#    (time () - $db_start_time) + timelocal(3, 54, 8, 1, 11, 99);
#    (time () - $db_start_time) + timelocal(3, 54, 13, 5, 1, 99);  # Tuesday
#    (time () - $db_start_time) + timelocal(0, 1, 18, 24, $month_map{'Dec'}, 99);
}
sub db_trace ( $ ) {
    printf STDERR "trace %s\n", $_[0] if $db_tracing;
}


## init/cleanup some globals
sub link_started () {
    db_trace ("link_started()");
    $ppp_offset =  $time_start - $time_dial_start;
    db_trace ("ppp_offset = $ppp_offset");
    foreach my $isp (@isps) {
	$records{$isp}= [];
    }
    $curr_secs_per_unit=1;
}
sub link_stopped () {
    db_trace ("link_stopped()");
    $isp_curr="";
}

sub tick () {
    update_state ();
    if ($state == $state_online) {
	foreach my $cmd (@commands_while_online) {
	    &$cmd;
	}
    }
}

## commands on transitions
sub state_trans_startup_to_offline () {
    db_trace ("state_trans_startup_to_offline");
    $state = $state_offline; foreach my $cmd (@commands_on_startup) { &$cmd; }
}
sub state_trans_offline_to_dialing () {
    db_trace ("state_trans_offline_to_dialing");
    $time_dial_start = db_time();
    $state = $state_dialing; foreach my $cmd (@commands_before_dialing) { &$cmd; }
}
sub state_trans_dialing_to_online () {
    db_trace ("state_trans_dialing_to_online");
    $time_start = db_time();
    link_started ();
    $state = $state_online; foreach my $cmd (@commands_on_connect) { &$cmd; }
}
sub state_trans_dialing_to_offline () {
    db_trace ("state_trans_dialing_to_offline");
    $state = $state_offline; foreach my $cmd (@commands_on_connect_failure) { &$cmd; }
    link_stopped();
}
sub state_trans_online_to_offline () {
    db_trace ("state_trans_online_to_offline");
    $time_disconnect = db_time();
    $state = $state_offline; foreach my $cmd (@commands_on_disconnect) { &$cmd; }
    write_ulog();
    link_stopped();
}

sub update_state () {
    my ($c, $count);
    my $x=0;
    while (defined ($count=(sysread SR, $c, 1))) {
	db_trace ("---->$c<----");
	$c="x" unless $count; # EOF
	$x=1 if ($c eq 'x' or $c eq 'f' or $c eq 't');
	if ($state == $state_dialing) {
	    state_trans_dialing_to_online () if ($c eq "c");
	    state_trans_dialing_to_offline () if ($c eq "f" or $c eq 'x');
	} elsif ($state == $state_online) {
	    state_trans_online_to_offline () if ($c eq "t");    
	} elsif ($state == $state_offline) {
	    state_trans_offline_to_dialing () if ($c eq "d");
	}
	last unless $count; # EOF
    }
    stop_log_scanner () if $x;
    # cleanup zombies
    unless (defined $sr_pid) { while (wait() != -1) { } }
}

sub get_sum ( $ ) {
    my ($isp) = @_;
    my $sum=0;
    my $tmp = $records{$isp};
    foreach my $i (@$tmp) {
	next unless defined $i;
	$sum += $$i[$offs_sum];
    }
    $sum;
}

sub format_ltime ( $ ) {
    my ($time) = @_;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime ($time); 
    sprintf ("%u-%02u-%02uT%02u:%02u:%02u%s",
	     $year+1900, $mon+1, $mday,
	     $hour, $min, $sec,
	     ($isdst ? "=DST" : ""));
}
sub parse_ltime ($) {
    my ($time)= @_;
    my $result=0;
    if ($time=~/^(\d{4})-(\d+)-(\d+)T(\d+):(\d+):(\d+)/) {
        # 2000-08-25T18:54:39
        #  1   2  3  4  5  6
	$result = timelocal ($6, $5, $4, $3, $2 - 1, $1 - 1900);
    } else { die; }
    $result;
}

#test# print STDERR format_ltime (parse_ltime ("2000-08-25T18:54:39")) . "\n";

## format a number of seconds since midnight to HH:MM:SS
#  the output is in 24h format.  the input must be <= 24h (in seconds)
sub format_day_time ( $ ) {
    my ($dt) = @_;
    use integer;
    my $sec = $dt % $secs_per_min;
    my $min = ($dt / $secs_per_min) % $mins_per_hour;
    my $hour = ($dt / $secs_per_hour);
    no integer;
    sprintf ("%02u:%02u:%02u%s", $hour, $min, $sec);
}
sub parse_day_time ( $ ) {
    my ($dt) = @_;
    use integer;
    my $result=-1;
    if ($dt =~ m/^(\d\d):(\d\d):(\d\d)$/)
    {
	$result= $1 * $secs_per_hour;
	$result+= $2 * $secs_per_min;
	$result+= $3;
    }
    no integer;
    $result;
}
#test# print STDERR format_day_time (parse_day_time ("23:59:58")) . "\n";

## write info about last connection into user owned logfile
sub write_ulog () {
    db_trace ("write_ulog()");
    flock (LOG, LOCK_EX);
    printf LOG ("<connect peer='%s' cost='%f' duration='%u' pppoffs='%u' start='%s' stop='%s' rate='%s' />\n",
		$isp_curr,
		get_sum ($isp_curr),
		$time_disconnect - $time_start,
		$time_start - $time_dial_start,
		format_ltime ($time_start),
		format_ltime ($time_disconnect),
		get_isp_tarif ($isp_curr));
    flock (LOG, LOCK_UN);
}

sub update_sum () {
    my $time_curr = db_time ();
    foreach my $isp (@isps) {
	next unless (get_isp_flag_active ($isp));
	my @tmp = Dialup_Cost::tarif (get_isp_tarif($isp), $time_curr);
	my $rates = $tmp[0];
	my $swp = $tmp[2];
	foreach my $rate (@$rates) {
	    my $tmp =  $records{$isp};
	    my $id = $$rate[$Dialup_Cost::offs_rate_id];
	    unless (defined $$tmp[$id]) {
		my @tmp2 = @template_rate_record;
		$$tmp[$id] = \ @tmp2;
	    }
	    my $rec = $records{$isp}[$$rate[$Dialup_Cost::offs_rate_id]];
	    $rec = $$tmp[$id];

	    if ($$rec[$offs_time_last] == 0) {
		$$rec[$offs_sum] = $$rate[$Dialup_Cost::offs_pfg_per_connection];
		$$rec[$offs_time_last] = $time_start - ($$rate[$Dialup_Cost::offs_sw_start_time] * $ppp_offset);
	    }
	    my $units_curr = ($time_curr - $$rec[$offs_time_last]) / $$rate[$Dialup_Cost::offs_secs_per_clock];
	    while ($$rec[$offs_time_last] < $time_curr) {
		die unless $$rate[$Dialup_Cost::offs_secs_per_clock] > 0;
		if ($isp eq $isp_curr and $$rate[$Dialup_Cost::offs_secs_per_clock] > 1) {
		    $curr_secs_per_unit = $$rate[$Dialup_Cost::offs_secs_per_clock];
		}
		$$rec[$offs_time_last] +=  $$rate[$Dialup_Cost::offs_secs_per_clock];
		$$rec[$offs_sum] +=  $$rate[$Dialup_Cost::offs_pfg_per_clock];
	    }
	}
    }
}

## start/stop "tail -F" scanner for "/var/log/ppp.log"
sub start_plog_scanner () {
  # start setuid log file scanner
    stop_log_scanner ();
    my $result=0;
    if ($sr_pid = open SR, "$progdir/status_reader.pl |") {
	my $c;
	if (((sysread SR, $c, 1) == 1) && $c eq "R" && fcntl SR, F_SETFL, O_NONBLOCK) {
	    $result=1;
	} else {
	    close SR;
	    undef $sr_pid;
	}
    }
    db_trace("sr_pid: $sr_pid");
    $result;
}

sub stop_log_scanner () {
    if (defined $sr_pid) {
	kill ('HUP', $sr_pid);
	close SR;
	undef $sr_pid;
    }
}

sub check_automatic_disconnect () {
    use integer;
    my $secs_used_in_unit = (db_time () - ($time_start - $ppp_offset)) % $curr_secs_per_unit;
    # perform deferred disconnection
    if ($flag_stop_defer and ($secs_used_in_unit + $unit_end_inaccuracy) > $curr_secs_per_unit) {
	$flag_stop_defer = 0;
	cb_disconnect ();
    }
    no integer;
}


sub dialup ( $ ) {
    my $isp = shift;
    start_plog_scanner () or die "$progname: cannot start status_reader.pl";
    my $cmd = get_isp_cmd($isp);
    $isp_curr = $isp;
    # exec external connect command asynchronous
    my $pid = fork();
    if ($pid == 0) {
	unless (exec ($cmd)) {
	    $state=$state_offline;
	    exec ('echo') or die; # FIXME: die will not work properly in a Tk callback
	}
    } elsif (! defined ($pid)) {
	$isp_curr = '';
    } else {
	db_trace("child_pid = $pid");
	update_state ();
    }
}

sub disconnect () {
    if ($isp_curr) {
	my $cmd = get_isp_disconnect_cmd ($isp_curr);
	qx($cmd);
    }
    0;
}



# configuration
sub escape_string ($) {
    my ($s) = @_;
    $s =~ s/\%/\%25/g;
    $s =~ s/\'/\%27/g;
    $s =~ s/\"/\%22/g;
    $s =~ s/\n/\%0A/g;
#    $s =~ s/\=/\%3d/g;
    $s;
}
sub unescape_string ($) {
    my ($s) = @_;
#    $s =~ s/\%3d/\=/g;
    $s =~ s/\%0A/\n/ig;
    $s =~ s/\%27/\'/g;
    $s =~ s/\%22/\"/g;
    $s =~ s/\%25/\%/g;
    $s;
}
#test# print STDERR unescape_string (escape_string ("double-quote: \" single-quote: ' percent-sign: %"));
sub read_config ($) {
    my ($file) =@_;
    if (open IN, ("$file")) {
	while (<IN>) {
	    if (/^\<([a-z]+) /) {
		my $tag = $1; 
		my @result;
		while (m/\b([a-z_]+)\=["']([^\"\']*)['"]/g) {
		    my ($key, $val) = ($1, unescape_string ($2));
		    if ($tag eq "peer") {
			if (defined $n2i{$key}) {
			    my $idx=$n2i{$key};
			    $result[ $idx ]=$val;
			    #db_trace ("key=<$key> val=<$val> idx=<$idx>");
			}
		    } elsif ($tag eq "gui") {
		#	$cfg_gui{"$key"} = $val;
		    }
		}
		if ($tag eq "peer" && defined $result[0]) {
		    $isps[$#isps+1]=$result[0];
		    set_isp_cfg (\@result);
		}
	    }
	}
	close IN;
	1;
    } else {
	0;
    }
}

# TODO-bw/28-Aug-00: allow selective saving
sub write_config ($) {
    my ($file) =@_;
    if (open OUT, (">$file")) {
	my $fi = '%s=\'%s\'';
	my $fmt_line = "<peer $fi $fi $fi $fi $fi $fi $fi />\n";
	foreach my $isp (@dm::isps) {
	    printf OUT ($fmt_line,
			$cfg_att_names[$cfg_isp], escape_string ($isp),
			$cfg_att_names[$cfg_cmd], escape_string (get_isp_cmd($isp)),
			$cfg_att_names[$cfg_disconnect_cmd], escape_string (get_isp_disconnect_cmd($isp)),
			$cfg_att_names[$cfg_label], escape_string (get_isp_label($isp)),
			$cfg_att_names[$cfg_color], escape_string (get_isp_color($isp)),
			$cfg_att_names[$cfg_tarif], escape_string (get_isp_tarif($isp)),
			$cfg_att_names[$cfg_active], escape_string (get_isp_flag_active($isp)));

	}
=pod
	{
	    my $line="";
	    my $count=0;
	    while (my ($key, $val) = each (%cfg)) {
		if ("$cfg_default{$key}" ne $val) {
		    $line .= "$key='" . escape_string ($val) . "' ";
		    db_trace ("key=<$key> val=<$val> count=<$count>");
		}
	    }
	    if ($line) {
		print OUT '<cfg ' . $line . "/>\n";
	    }
	}
=cut
	close OUT;
	1;
    } else {
	0;
    }
}

sub save_config () { write_config ($cfg_file_usr); }

read_config((-e $cfg_file_usr) ? $cfg_file_usr : $cfg_file) or die;
Dialup_Cost::read_data((-e $cost_file_usr) ? $cost_file_usr : $cost_file);

# open log file
if (defined $cost_out_file) {
    open (LOG, ">>$cost_out_file") or die;
    LOG->autoflush (1);
    db_trace("LOG open");
#    close LOG unless (flock (LOG, LOCK_EX | LOCK_NB));
}


1;
END { }       # module clean-up code here (global destructor)
