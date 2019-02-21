package dm;
## $Id: dm.pm,v 1.4 2000/09/10 06:13:01 bertw Exp bertw $

use strict;
use Time::Local;
use Fcntl;
use Fcntl qw(:flock);
#use IO::Handle;
use Graphs;
use Dialup_Cost;
use Utils;
use Pon;

BEGIN {
    use Exporter   ();
    use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
    $VERSION = do { my @r = (q$Revision: 1.4 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };
    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    %EXPORT_TAGS = ();
    @EXPORT_OK   = qw();
}
use vars @EXPORT_OK;
use vars qw(@isps $isp_curr $state_startup @cfg_labels @cfg_isp $cost_out_file
	    %isp_cfg_map $time_start $curr_secs_per_unit
            %cfg_sock
	    $flag_stop_defer $flag_disconnect_now $flag_connect_now $flag_terminate_now
	    $state $state_startup $state_offline
	    $state_dialing $state_online
	    @commands_on_startup  @commands_before_dialing  @commands_on_connect
	    @commands_on_connect_failure @commands_on_disconnect
	    $cfg_isp $cfg_cmd $cfg_disconnect_cmd $cfg_label $cfg_color
	    $cfg_tarif $cfg_active $cfg_SIZE
	    $ppp_offset);


##============== State Machine ===================
# hooks for commands called on transitions (writable!)
@commands_on_startup = (); @commands_before_dialing = (); @commands_on_connect = ();
 @commands_on_connect_failure = (); @commands_on_disconnect = ();
# state identifiers
($state_startup, $state_offline, $state_dialing,
 $state_online) = (0..20);
# current state
$state=$state_startup; 
##================ Peers ==========================
@isps=();           # list of all peer names
$isp_curr='';       # current peer name or empty when state is "offline".
%isp_cfg_map=();    # configuration arrays for each peer
($cfg_isp, $cfg_cmd, $cfg_disconnect_cmd,
 $cfg_label, $cfg_color, $cfg_tarif, $cfg_active,
 $cfg_SIZE) = (0..20); # indexes of configuration attributes
my $dm_config_version="1.1";
##================ Times ==========================
$curr_secs_per_unit=0;  # ???
$time_start=0;          # absolute time when PPP has established
$ppp_offset=0;          # seconds used by dialing, connecting, link up on current/last connection
## ============ Preferences ========================
my %cfg_sock_default=('.config_tag' => 'sock',
		      quick_connect_duration=>240, # used to predict cheapest ISP when connecting via signal handler
		      use_sockets=>1,
		      ip_ui_port => 8889,
		      ip_dialer_hostname => 'localhost',
		      ip_dialer_port => 8888);
%cfg_sock = %cfg_sock_default;
$cfg_sock{'.config_default'}=\%cfg_sock_default;
##================ Misc ===========================
$cost_out_file=$ENV{"HOME"} . "/.dialup_cost.log";
$flag_stop_defer=0;     # if not 0 then disconnect just before next pay-unit
$flag_disconnect_now=0; # initiate disconnect from signal-handlers
$flag_terminate_now=0;  # initiate terminating from signal-handlers
$flag_connect_now=0;    # initiate connect from signal-handlers

# all file-scoped lexicals must be created before
# the functions below that use them.

my $sock_mode=0;  # 0: no sockets, 1: shared peer,  2: exclusive peer

##--- Commands Issued Each Tick
my @commands_while_online = (\&update_sum, \&check_automatic_disconnect);
my $time_disconnect = 0;
my $time_dial_start = 0;
my $db_start_time = time ();
my $sr_pid;
my $ppp_offset_avg=30;     # seconds used by dialing, connecting, link up according to history logfile
my %ppp_offset_avg;        # initial ppp_offset_avg for some (!) ISPs according to  history logfile
my $update_state_hook = sub {};
# file-private lexicals go here

##--- constants
$0 =~ m!^(.*)/([^/]*)$! or die "path of program file required (e.g. ./$0)";
my ($progdir, $progname) = ($1, $2);
my %records;
my @template_rate_record = (0, 0);  # a template object for cloning
my ($offs_sum, $offs_time_last) = (0..20);
my @cfg_att_names = ('id', 'up_cmd', 'down_cmd', 'label', 'color', 'rate', 'active_flag');
my %n2i; foreach my $i (0..$#cfg_att_names) { $n2i{$cfg_att_names[$i]} = $i; }
my $unit_end_inaccuracy=5; # hangup this seconds before we think a unit ends
my $db_tracing = defined ($ENV{'DB_TRACING'});
my $cfg_file="${progdir}/dialup_manager.cfg";
my $cfg_file_usr=$ENV{"HOME"} . "/.tkdialup/app.cfg";
my $cost_file="${progdir}/dialup_cost.data";
my $cost_file_usr=$ENV{"HOME"} . "/.dialup_cost.data";

# make all your functions, whether exported or not;
# remember to put something interesting in the {} stubs

##--- Protos
 sub get_isp_tarif( $ );
 sub get_isp_cmd( $ );
 sub get_isp_disconnect_cmd( $ );
 sub get_isp_label( $ );
 sub get_isp_color( $ );
 sub get_isp_flag_active( $ );
 sub get_isp_cfg( $$ );
 sub set_isp_cfg( $ );
 sub remove_isp( $ );
 sub db_trace ( $ );
 sub link_started ();
 sub link_stopped ();
 sub tick ();
 sub state_trans_startup_to_offline ();
 sub get_sum ( $ );
 sub format_day_time ( $ );
 sub parse_day_time ( $ );
 sub write_ulog ();
 sub update_sum ();
 sub start_plog_scanner ();
 sub stop_log_scanner ();
 sub check_automatic_disconnect ();
 sub dialup ( $ );
 sub disconnect ();
 sub read_config( $ );
 sub write_config( $$$ );
 sub init_ppp_offset_avg();
 sub get_ppp_offset_avg( $ );
 sub predict_cost( $$$ );
 sub init();
##----


sub get_isp_tarif( $ ) { my $cfg=$isp_cfg_map{$_[0]}; $$cfg[$cfg_tarif]; }   # payment-id of ISP
sub get_isp_cmd( $ ) { my $cfg=$isp_cfg_map{$_[0]}; $$cfg[$cfg_cmd]; }       # external dialup command of ISP
sub get_isp_disconnect_cmd( $ ) { my $cfg=$isp_cfg_map{$_[0]}; $$cfg[$cfg_disconnect_cmd]; }       # external disconnect command of ISP
sub get_isp_label( $ ) { my $cfg=$isp_cfg_map{$_[0]}; $$cfg[$cfg_label]; }   # label on connect button of ISP
sub get_isp_color( $ ) { my $cfg=$isp_cfg_map{$_[0]}; $$cfg[$cfg_color]; }   # color in cost graph of ISP
sub get_isp_flag_active( $ ) { my $cfg=$isp_cfg_map{$_[0]}; $$cfg[$cfg_active]; }   # string of single letter flags
sub get_isp_cfg( $$ ) { my $cfg=$isp_cfg_map{$_[0]}; $$cfg[$_[1]]; }         # one of the item of ISP selected by INDEX
sub set_isp_cfg( $ ) { my ($a)=@_; $isp_cfg_map{$$a[0]} = $a; }              # store/replace CFG by reference

sub remove_isp_by_name( $ ) {
    my $isp = shift;
    db_trace("remove_isp($isp)");
    undef $isp_cfg_map{$isp};
    for my $i ($[..$#isps) {
	if ($isps[$i] eq $isp) {
	    splice (@isps, $i, 1);
	    last;
	}
    }
}
sub remove_isp_by_index( $ ) {
    my $isp_idx = shift;
    db_trace("remove_isp_by_index($isp_idx)");
    undef $isp_cfg_map{$isps[$isp_idx]};
    splice (@isps, $isp_idx, 1);
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
  $update_state_hook = sub {};
}

sub f( $ ) {
  my $connect_duration=shift;

  my $curr_time = Utils::db_time();
  my @tem;
  foreach my $isp (@isps) {
    next unless (get_isp_flag_active ($isp));
    my $cost = predict_cost ($isp, $curr_time, $connect_duration);
    $tem[++$#tem] = [$isp, $cost];
  }
  @tem = sort {$$a[1] <=> $$b[1]} @tem;
  \@tem;
}

sub dialup_cheapest( $ ) {
  my $duration=shift;
  db_trace("dialup_cheapest(duration=$duration)");
  my $tem = f($duration);
  my $cheapest = $$tem[0];
  dialup ($$cheapest[0]);
}

sub tick () {
  &$update_state_hook ();
  if ($state == $state_online) {
    foreach my $cmd (@commands_while_online) {
      &$cmd;
    }
  }

  if ($flag_disconnect_now or $flag_terminate_now) {
    $flag_disconnect_now=0;
    $flag_stop_defer=0;
    disconnect () if ($state == $state_dialing  or $state == $state_online) ;
  }
  if ($flag_terminate_now) {
    $flag_connect_now = 0;
    exit (0) if ($state == $state_offline);
  }
  if ($flag_connect_now) {
    $flag_connect_now=0;
    dialup_cheapest ($cfg_sock{'quick_connect_duration'}) if ($state == $state_offline);
  }
}

## commands on transitions
sub state_trans_startup_to_offline () {
    db_trace ("state_trans_startup_to_offline");
    $state = $state_offline; foreach my $cmd (@commands_on_startup) { &$cmd; }
}
my $state_trans_offline_to_dialing = sub {
    db_trace ("state_trans_offline_to_dialing");
    $time_dial_start = Utils::db_time();
    $state = $state_dialing; foreach my $cmd (@commands_before_dialing) { &$cmd; }
};
my $state_trans_dialing_to_online = sub {
    db_trace ("state_trans_dialing_to_online");
    $time_start = Utils::db_time();
    link_started ();
    $state = $state_online; foreach my $cmd (@commands_on_connect) { &$cmd; }
};
my $state_trans_dialing_to_offline = sub  {
    db_trace ("state_trans_dialing_to_offline");
    $state = $state_offline; foreach my $cmd (@commands_on_connect_failure) { &$cmd; }
    link_stopped();
};
my $state_trans_online_to_offline = sub {
    db_trace ("state_trans_online_to_offline");
    $time_disconnect = Utils::db_time();
    $state = $state_offline; foreach my $cmd (@commands_on_disconnect) { &$cmd; }
    write_ulog();
    link_stopped();
};

# fetch state reports using an external setuid log file scanner
# IPC by pipe (status_reader.pl was executed by popen())
my $update_state_unix = sub {
    my ($c, $count);
    my $x=0;
    while (defined ($count=(sysread SR, $c, 1))) {
	db_trace ("---->$c<----");
	$c="x" unless $count; # EOF
	$x=1 if ($c eq 'x' or $c eq 'f' or $c eq 't');
	if ($state == $state_dialing) {
	    &$state_trans_dialing_to_online () if ($c eq "c");
	    &$state_trans_dialing_to_offline () if ($c eq "f" or $c eq 'x');
	} elsif ($state == $state_online) {
	    &$state_trans_online_to_offline () if ($c eq "t" or $c eq 'x')
	} elsif ($state == $state_offline) {
	    &$state_trans_offline_to_dialing  if ($c eq "d");
	}
	last unless $count; # EOF
    }
    stop_log_scanner () if $x;
    # cleanup zombies
    unless (defined $sr_pid) { while (wait() != -1) { } }
};

# check state reported by external dialer
# IPC by checking for existing filenames on a local filesystem
my $update_state_w32ras_nonsock = sub {
  syswrite (W32RAS, "Cs\n");
  if ($state == $state_dialing) {
    &$state_trans_dialing_to_online () if (-e "C:/WINDOWS/TEMP/tkdialup_online");
    &$state_trans_dialing_to_offline () if (-e "C:/WINDOWS/TEMP/tkdialup_offline");
  } elsif ($state == $state_online) {
    &$state_trans_online_to_offline () if (-e "C:/WINDOWS/TEMP/tkdialup_offline");
  } elsif ($state == $state_offline) {
    &$state_trans_offline_to_dialing  if (-e "C:/WINDOWS/TEMP/tkdialup_dialing");
  }
};

# check state reported by external dialer
# IPC by polling our socket for messages
my $update_state_w32ras = sub {
  my $c;
  my $x=0;
  while (dmsock::poll_socket(0)) {
    db_trace("poll");
    my $s=dmsock::recv_dm_string();
    next unless substr($s, 0, 1) eq 'S';
    my $c=substr($s, 1, 1);
    db_trace ("---->$c<----");
    $x=1 if ($c eq 'x' or $c eq 'f' or $c eq 't');
    if ($state == $state_dialing) {
      &$state_trans_dialing_to_online () if ($c eq "c");
      &$state_trans_dialing_to_offline () if ($c eq "f" or $c eq 'x');
    } elsif ($state == $state_online) {
      &$state_trans_online_to_offline () if ($c eq "t" or $c eq 'x');
    } elsif ($state == $state_offline) {
      &$state_trans_offline_to_dialing  if ($c eq "d");
    }
  }
};


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


#test# print STDERR Utils::format_ltime (Utils::parse_ltime ("2000-08-25T18:54:39")) . "\n";

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
  if (open (LOG, ">>$cost_out_file")) {
#    flock (LOG, LOCK_EX);
    printf LOG ("<connect peer='%s' cost='%f' duration='%u' pppoffs='%u' start='%s' stop='%s' rate='%s' />\n",
		$isp_curr,
		get_sum ($isp_curr),
		$time_disconnect - $time_start,
		$time_start - $time_dial_start,
		Utils::format_ltime ($time_start),
		Utils::format_ltime ($time_disconnect),
		get_isp_tarif ($isp_curr));
#    flock (LOG, LOCK_UN);
    close LOG;
  }
}

sub update_sum () {
    my $time_curr = Utils::db_time ();
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
    my $secs_used_in_unit = (Utils::db_time () - ($time_start - $ppp_offset)) % $curr_secs_per_unit;
    # perform deferred disconnection
    if ($flag_stop_defer and ($secs_used_in_unit + $unit_end_inaccuracy) > $curr_secs_per_unit) {
	$flag_stop_defer = 0;
	disconnect ();
    }
    no integer;
}

my $dialup_fork = sub {
  my ($isp, $cmd) = @_;
  db_trace("dialup_fork ($isp, $cmd)");
  $update_state_hook=$update_state_unix;
  disconnect ();		#XXX
  start_plog_scanner () or die "$progname: cannot start status_reader.pl";
  $isp_curr = $isp;
  # exec external connect command asynchronous
  my $pid = fork();
  if ($pid == 0) {
    unless (exec ($cmd)) {
      $state=$state_offline;
      exec ('echo') or die;	# FIXME: die will not work properly in a Tk callback
    }
  } elsif (! defined ($pid)) {
    $isp_curr = '';
  } else {
    db_trace("child_pid = $pid");
    &$update_state_hook ();
  }
};

my $dialup_system = sub {
  my ($isp, $cmd) = @_;
  $update_state_hook=$update_state_unix;
  db_trace("dialup_system ($isp, $cmd)");
  disconnect ();		#XXX
  start_plog_scanner () or die "$progname: cannot start status_reader.pl";
  $isp_curr = $isp;
  qx($cmd);
};


my $hangup_system = sub {
  my ($isp, $cmd) = @_;
  db_trace("hangup_system ($isp, $cmd)");
  qx($cmd);
};

my $dialup_Pon = sub {
  my ($isp, $cmd) = @_;
  $update_state_hook=$update_state_unix;
  db_trace("dialup_Pon ($isp, $cmd)");
  disconnect ();		#XXX
  start_plog_scanner () or die "$progname: cannot start status_reader.pl";
  $isp_curr = $isp;
  Pon::dialup_isp($cmd);
};
my $hangup_Pon = sub {
  my ($isp, $cmd) = @_;
  db_trace("hangup_system ($isp, $cmd)");
  Pon::hangup_isp($cmd);
};

my $dialup_w32ras_nosock = sub {
  my ($isp, $ras_isp) = @_;
  $update_state_hook = $update_state_w32ras_nonsock;
  db_trace("dialup_w32ras ($isp, $ras_isp)");
  $isp_curr = $isp;
  my $cmd = "DCd$ras_isp\nD";
  syswrite (W32RAS, $cmd) or die;
};

my $hangup_w32ras_nosock = sub {
  my ($isp, $ras_isp) = @_;
  db_trace("hangup_w32ras ($isp, $ras_isp)");
  $isp_curr = $isp;
  my $cmd = "DCh\nD";
  syswrite (W32RAS, $cmd) or die;
};

my $dialup_w32ras_sock = sub {
  my ($isp, $ras_isp) = @_;
  $update_state_hook=$update_state_w32ras;
  db_trace("dialup_w32ras_sock ($isp, $ras_isp)");
  $isp_curr = $isp;
  dmsock::send_string("Li"); # XXX login forever
  my $cmd = "Cd$ras_isp";
  dmsock::send_string($cmd);
};

my $hangup_w32ras_sock = sub {
  my ($isp, $ras_isp) = @_;
  db_trace("hangup_w32ras_sock ($isp, $ras_isp)");
  $isp_curr = $isp;
  my $cmd = "Ch";
  dmsock::send_string($cmd);
};


my $dialup_hook=$dialup_fork;

sub dialup ( $ ) {
  my $isp = shift;
  my $cmd = get_isp_cmd($isp);
  if ($cmd =~ s/^\&?w32ras\s+(.+)$/$1/) {
    if ($sock_mode) {
      &$dialup_w32ras_sock ($isp, $cmd);
    } else {
      &$dialup_w32ras_nosock ($isp, $cmd);
    }
  } elsif ($cmd =~ s/^\&pppd\s+(.+)$/$1/) {
    &$dialup_Pon ($isp, $cmd);
  } elsif ($cmd =~ s/^(.+)\&\s*$/$1/) {
    &$dialup_fork ($isp, $cmd);
  } else {
    &$dialup_system ($isp, $cmd);
  }
}

sub disconnect () {
  if ($isp_curr) {
    my $isp = $isp_curr;
    my $cmd = get_isp_disconnect_cmd ($isp_curr);
    if ($cmd =~ s/^\&?w32ras\s+(.+)$/$1/) {
      if ($sock_mode) {
	&$hangup_w32ras_sock ($isp, $cmd);
      } else {
	&$hangup_w32ras_nosock ($isp, $cmd);
      }
    } elsif ($cmd =~ s/^\&pppd\s+(.+)$/$1/) {
      &$hangup_Pon ($isp, $cmd);
    } elsif ($cmd =~ s/^(.+)\&\s*$/$1/) {
      #      &$hangup_fork ($isp, $cmd);
    } else {
      &$hangup_system ($isp, $cmd);
    }
  }
}

# configuration
sub read_config( $ ) {
    my ($file) =@_;
    my $result=0;
    my $section="dm-config";
    my $config_version=$dm_config_version;
    if (open IN, ("$file")) {
	while (<IN>) {
	    if (m/^\<$section\s+version=[\"]([^\"]+)[\"]\s*\>/) {
		my $current_version="$1";
		while (<IN>) {
		    last if (m/\<\/$section\s*\>/);
		    next if ($current_version ne $config_version);
		    if (/^\<record /) {
			$result++; #XXX-bw/01-Sep-00
			my @record;
			while (m/\b([a-z_]+)\=["']([^\"\']*)['"]/g) {
			    my ($key, $val) = ($1, Utils::unescape_string ($2));
			    if (defined $n2i{$key}) {
				my $idx=$n2i{$key};
				$record[ $idx ]=$val;
				#db_trace ("key=<$key> val=<$val> idx=<$idx>");
			    }
			}
			if (defined $record[0]) {
			    $isps[$#isps+1]=$record[0];
			    set_isp_cfg (\@record);
			}
		    }
		}
	    }
	}
	close IN;
	$result } else { 0 }
}

# TODO-bw/01-Sep-00: implement file locking. cleanup the code.
sub write_config( $$$ ) {
    my ($file, $section, $cfg_arg) =@_;
    db_trace("write_config($file, $section, $cfg_arg)");
    my $requested_version=($section eq "dm-config" ? $dm_config_version : $$cfg_arg{'.config_version'});

    # create config file if not exist
    if (! -e $file) {
	if (open OUT, (">$file")) {
	   close OUT;
        }
    }
    # read and write config file, keep all sections except requested $section of $version
    if (open IN, ("$file")) {
	my @content;
	my $section_idx=-1;
	while (<IN>) {
	    if (m/^\<([a-z\-_]+)\s+version=[\"]([^\"]+)[\"]\s*\>/
		and ($1 eq $section) and ($2 eq $requested_version)) {
		my $version=$1;
		$section_idx=$#content;
		while (<IN>) {
		    last if (m/^\<\/$section\>/);
		}
	    } else {
		$content[$#content+1]=$_;
	    }
	}
	close IN;
	if (open OUT, (">$file")) {
	    for my $i (0..$section_idx) {
		print OUT $content[$i];
		db_trace("i1=$i");
	    }
	    if ($section eq "dm-config") {
		print OUT "<dm-config version=\"$dm_config_version\">\n<peers>\n";
		my $fi = '%s=\'%s\'';
		my $fmt_line = "<record $fi $fi $fi $fi $fi $fi $fi />\n";
		foreach my $isp (@dm::isps) {
		    printf OUT ($fmt_line,
				$cfg_att_names[$cfg_isp], Utils::escape_string ($isp),
				$cfg_att_names[$cfg_cmd], Utils::escape_string (get_isp_cmd($isp)),
				$cfg_att_names[$cfg_disconnect_cmd], Utils::escape_string (get_isp_disconnect_cmd($isp)),
				$cfg_att_names[$cfg_label], Utils::escape_string (get_isp_label($isp)),
				$cfg_att_names[$cfg_color], Utils::escape_string (get_isp_color($isp)),
				$cfg_att_names[$cfg_tarif], Utils::escape_string (get_isp_tarif($isp)),
				$cfg_att_names[$cfg_active], Utils::escape_string (get_isp_flag_active($isp)));

		}
		print OUT "</peers>\n</dm-config>\n";
	    } else {
		my $config_version=$$cfg_arg{'.config_version'};
		my $content="";
		while (my ($config_tag, $cfg_hash) = each (%$cfg_arg)) {
		    next unless substr($config_tag, 0, 1) ne "."; #skip special keys
		    my $cfg_default_hash=$$cfg_hash{'.config_default'};
		    my $line="";
		    my $count=0;
		    while (my ($key, $val) = each (%$cfg_hash)) {
			if (substr($key, 0, 1) ne "." && "$$cfg_default_hash{$key}" ne $val) {
			    $line .= "$key=\"" . Utils::escape_string ($val) . "\" ";
			    db_trace ("key=<$key> val=<$val> count=<$count>");
			}
		    }
		    $content .= "<$config_tag $line/>\n";
		}
		if ($content) {
		    print OUT "<$section version=\"$config_version\">\n" . $content . "</$section>\n";
		}
	    }
	    for my $i ($section_idx+1..$#content) {
		db_trace("i=$i");
		print OUT $content[$i];
	    }
		close OUT;
	    1 } else { 0 }
	1 } else { 0 }
}

sub save_config () { write_config ($cfg_file_usr, "dm-config", 0); }

=pod
sub xxx {
    my @result;
    foreach my $isp (@dm::isps) {
	my %cfg;
	@result[$#result+1]=\%cfg;
	$cfg{$cfg_att_names[$cfg_isp]} = $isp;
	$cfg{$cfg_att_names[$cfg_cmd]} = get_isp_cmd($isp);
	$cfg{$cfg_att_names[$cfg_disconnect_cmd]} = get_isp_disconnect_cmd($isp);
	$cfg{$cfg_att_names[$cfg_label]} = get_isp_label($isp);
	$cfg{$cfg_att_names[$cfg_color]} = get_isp_color($isp);
	$cfg{$cfg_att_names[$cfg_tarif]} = get_isp_tarif($isp);
	$cfg{$cfg_att_names[$cfg_active]} = get_isp_flag_active($isp);
    }
}
=cut

# set $ppp_offset_avg and %ppp_offset_avg according to history logfile
sub init_ppp_offset_avg() {
  my $count=0;
  my $sum;
  my %count;
  my %sum;
  if (open (IN, "$cost_out_file")) {
  seek (IN, -1024 * 100, 2) or seek(IN, 0, 0);
  my @in = <IN>;
  db_trace("\@in lines: $#in");
    while (defined ($_ = pop (@in))) {
      if (/^\<connect /) {
	my $pppoffs= $1 if (m/\bpppoffs=["'](\d+)['"]/);
	next unless defined ($pppoffs);
	my $peer= $1 if (m/\bpeer=["'](\w*)['"]/);
	next unless defined ($peer);
	if ($count < 20) {
	  ++$count;
	  $sum+=$pppoffs;
	}
	if (!defined $count{$peer} or $count{$peer} < 20) {
	  ++$count{$peer};
	  $sum{$peer}+=$pppoffs;
	}
      }
    }
    close IN;
    use integer;
    ($ppp_offset_avg = $sum / $count) if ($count > 0);
    while (my ($peer, $count) = each (%count)) {
      ($ppp_offset_avg{$peer} = $sum{$peer} / $count) if ($count > 0);
      db_trace("ppp_offset_avg{$peer}=$ppp_offset_avg{$peer} count=$count");
    }
    no integer;
  }
}

sub get_ppp_offset_avg( $ ) {
  my $peer=shift;
  defined $ppp_offset_avg{$peer} ? $ppp_offset_avg{$peer} : $ppp_offset_avg;
}

sub save_cost_data () {
  my $str=Dialup_Cost::write_data_ff();
  if (open OUT, (">$cost_file_usr")) {
    print OUT $str;
    close (OUT);
  }
}


# predict real cost for ISP if dialing starts at STARTING_TIME.
# DURATION is the time in seconds the PPP link is up (without dialup
# time!)
sub predict_cost( $$$ ) {
  my ($isp, $starting_time, $duration)=@_;
  my $result=-1;
  my $xmax=$duration;
  my $xscale=1;
  my $xoffs=0;
  my $yoffs=0;
  my $yscale=-1;
  my $height=1;

  my $time=$starting_time;
  my $restart_x=0; 
  my $restart_y=0;
  my $part_of_previous_rate=0;
 restart: {
    my $restart_x1=$restart_x;
    my $restart_y1=$restart_y;
    $restart_x = 0; $restart_y = 0;
    my $flag_do_restart=0;
    my @graphs=();
    my @args=();
    my @tmp = Dialup_Cost::tarif (dm::get_isp_tarif($isp), $time + $restart_x1);
    my $tar = $tmp[0];		# rate list
    my $swp = $tmp[2];		# absolute switchpoints (time of changing rates)
    my ($x, $y) = (0, 0);
    my $is_linear=1;
    my @data=();
    my $next_switch=9999999999;
    foreach my $a (@$tar) {
      my $offs_time = $$a[$Dialup_Cost::offs_sw_start_time] * dm::get_ppp_offset_avg($isp);
      my $offs_units; { use integer;  $offs_units =  $offs_time / $$a[$Dialup_Cost::offs_secs_per_clock] + 1};
      my $sum += $offs_units * $$a[$Dialup_Cost::offs_pfg_per_clock] + $$a[$Dialup_Cost::offs_pfg_per_connection];
      foreach my $i (@$swp) {
	$next_switch = $i if ($next_switch > $i);
      }
      if ($$a[$Dialup_Cost::offs_secs_per_clock] <= 1) {
	# handle pseudo linear graphs (like 1 second per clock) ###############################
	my $xmax2 =  $xmax;
	if ($next_switch < $xmax) {
	  $restart_x = $xmax2 = $next_switch;
	  die if $restart_x < $restart_x1;
	  $flag_do_restart=1;
	}
	if (! $restart_x1) {
	  $graphs[$#graphs+1]
	    = [ 0, $sum,
		$xmax2, $sum + $xmax2 *  $$a[$Dialup_Cost::offs_pfg_per_clock] / $$a[$Dialup_Cost::offs_secs_per_clock] ];
	} else {
	  $graphs[$#graphs+1]
	    = [ $restart_x1, 0,
		$xmax2, ($xmax2 - $restart_x1) *  $$a[$Dialup_Cost::offs_pfg_per_clock] / $$a[$Dialup_Cost::offs_secs_per_clock] ];
	}

      } else {
	# handle stair graphs (like 150 seconds per clock) ######################################
	my @g = ($restart_x1) ? ()              : (0, $sum);
	my $u = ($restart_x1) ? 0               : $offs_units+1;
	my $i = ($restart_x1) ? $restart_x1 + 1 : $$a[$Dialup_Cost::offs_secs_per_clock]  - $offs_time;

	while (($i <= $xmax) or ($i - $restart_x1 > $next_switch)) { # FIXME
	  if ($i - $restart_x1 > $next_switch) { # switchpoint reached
	    $restart_x = $next_switch;
	    $flag_do_restart = 1;
	    $part_of_previous_rate 
	      = (($next_switch - ($i - $restart_x1 -  $$a[$Dialup_Cost::offs_secs_per_clock]))
		) / $$a[$Dialup_Cost::offs_secs_per_clock];
	    last;
	  }
	  $g[$#g+1] = $i-1;
	  $g[$#g+1] = $#g > 1 ? $g[$#g-1] : 0;
	  $g[$#g+1] = $i;
	  $g[$#g+1] = $u++ * $$a[$Dialup_Cost::offs_pfg_per_clock] + $$a[$Dialup_Cost::offs_pfg_per_connection];

	  $i+= $$a[$Dialup_Cost::offs_secs_per_clock] * (1 - $part_of_previous_rate);
	  $part_of_previous_rate = 0;
	}
	if (! $flag_do_restart) {
	  if ($i != $xmax) {
	    $g[$#g+1] = $xmax;
	    $g[$#g+1] = $g[$#g-1];
	  }
	} else {
	  # we need common last x  for add_graph()
	  $g[$#g+1] = $next_switch;
	  $g[$#g+1] = $g[$#g-1];
	}
	$graphs[$#graphs+1] = \ @g;
      }
    }
    my $gref =  $graphs[0];
    my @graph = @$gref;
    if ($#graphs > 0) {
      for (my $i=1; $i <= $#graphs; $i++) {
	@graph = add_graphs ($gref, $graphs[$i]);
      }
    }
    for (my $i=1; $i <= $#graph; $i+=2) {
      $graph[$i] += $restart_y1;
    }
    {
      my $t=0;
      foreach my $i (@graph) {
	if (++$t%2) {
	  $args[$#args+1] = $i * $xscale + $xoffs;
	} else {
	  # y
	  $args[$#args+1] = -($i * $yscale - $height + $yoffs);
	}
      }
    }

    #	  $args[$#args+1] = '-fill';
    #	  $args[$#args+1] = dm::get_isp_color($isp);
    #	  $canvas->createLine (@args);

    if ($flag_do_restart) {
      $restart_y = $graph[$#graph];
      goto restart if $flag_do_restart;
    }
    db_trace ("isp: $isp args: @args");
    $result=$args[$#args];
  }
  $result;
}

#=================================================================
sub init() {
  init_ppp_offset_avg ();
  read_config($cfg_file_usr) or read_config($cfg_file);
  Dialup_Cost::read_data((-e $cost_file_usr) ? $cost_file_usr : $cost_file);

  if (-x "$progdir/w32ras_dialer2.exe" or
      -x  "$progdir/w32ras_dialer2.exe") {
    if ($cfg_sock{'use_sockets'}) {
      require dmsock;
      dmsock::init($cfg_sock{'ip_ui_port'},
		   $cfg_sock{'ip_dialer_hostname'},
		   $cfg_sock{'ip_dialer_port'}) or die;
      $sock_mode = 1;
      if ($cfg_sock{'ip_dialer_hostname'} eq 'localhost') {  # XXX we should allow shared localhost peers too
	# start local w32ras_dialer
        $sock_mode = 2;
	my $remote_port = dmsock::get_remote_port();
	my $child;
	if (not defined ($child = fork ())) {
	  die "cannot fork";
	} elsif (!$child) {
	  exec "$progdir/w32ras_dialer2.exe -p $remote_port" or die;
	} else {
	}
      }
    } else {
      open (W32RAS, "|$progdir/w32ras_dialer.exe");
    }
  }

  $SIG{'USR1'}=sub { unless ($flag_stop_defer) { $flag_stop_defer=1 } else { $flag_disconnect_now=1 } };
  $SIG{'USR2'}=sub { $flag_connect_now=1; };
  $SIG{'INT'}=sub { $flag_terminate_now=1; };
}

1;
END {      # module clean-up code here (global destructor)
  if ($sock_mode == 2) {
    # terminate our exlusive dialer
    dmsock::send_string("Li"); # we must login before sending a command
    dmsock::send_string("Cq"); # send quit command
    dmsock::destroy_socket();  #
  }
}
