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


#$SIG{'CHLD'}='IGNORE'; # avoid zombie child processes
#$SIG{'HUP'}='IGNORE'; # allow terminating childs using  kill('HUP', -$$)

my $APPNAME="tkdialup";
my $applang="de"; # de | en
#$applang="en"; # de | en


my @isps;
my %isp_cfg_map;
my ($cfg_isp, $cfg_cmd, $cfg_disconnect_cmd, $cfg_label, $cfg_color, $cfg_tarif, $cfg_active, $cfg_SIZE) = (0..20);
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
# data for config editors
my @cfg_labels = ('Name', 'Up Cmd', 'Down Cmd', 'Label', 'Farbe', 'Tarif', 'Visible');
my @cfg_types =  ('text', 'text',   'text',      'text', 'color', 'text',  'flag');

my $ppp_offset=30;
my $unit_end_inaccuracy=5; # hangup this seconds before we think a unit ends
my $db_ready = 0; # debugging switch
my $db_tracing = defined ($ENV{'DB_TRACING'});
my $isp_curr= defined $ARGV[0] ? $ARGV[0] : '';
my $sr_pid;
my $cfg_file="${progdir}/dialup_manager.cfg";
my $cfg_file_usr=$ENV{"HOME"} . "/.dialup_manager.cfg";
my $cost_file="${progdir}/dialup_cost.data";
my $cost_file_usr=$ENV{"HOME"} . "/.dialup_cost.data";
my $cost_out_file=$ENV{"HOME"} . "/.dialup_cost.log";
my $flag_stop_defer=0;  # if not 0 then stop just before next pay-unit

# constants
my $days_per_week = 7;
my $hours_per_day = 24;
my $mins_per_hour = 60;
my $mins_per_day = $mins_per_hour * $hours_per_day;
my $secs_per_min = 60;
my $secs_per_hour = $secs_per_min * $mins_per_hour;
my $secs_per_day = $secs_per_hour * $hours_per_day;

#### Locale ####
# Locale Defaults (English)
my @wday_names=('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday');
my %LOC;
#---- File Menu
$LOC{'menu_file'}="File";
$LOC{'menu_file_hangup_now'}="Hangup now";
$LOC{'menu_file_hangup_now.help'}='Disconnect immediatly by issuing "Down Cmd"';
$LOC{'menu_file_hangup_defer'}="Hangup later";
$LOC{'menu_file_hangup_defer.help'}='Disconnect just before the current unit would end';
$LOC{'menu_file_save'}="Save Configuration";
$LOC{'menu_file_save.help'}='Keep all configuration changes permanently';
$LOC{'menu_file_quit'}="Quit";
$LOC{'menu_file_quit.help'}='Disconnect and terminate this "tkdialup" process immediatly.';
#---- Edit Menu
$LOC{'menu_edit'}="Edit";
$LOC{'menu_edit_options'}="Options";
$LOC{'menu_edit_options.help'}='Change Programm settings';
$LOC{'menu_edit_peer_options'}="Peer Options";
$LOC{'menu_edit_peer_options.help'}='Run a configuration editor. Its not full implemented yet
You can edit, apply and save  existing peer configurations like:
dialup command, hangup command, label, color, rate-name, visibility

You can show a rate but you cannot edit rates date.';
$LOC{'menu_edit_graph_options'}="Graph Options";
$LOC{'menu_edit_graph_options.help'}='Edit  background and ruler colors of graph window';
#---- View Menu
$LOC{'menu_view'}="View";
$LOC{'menu_view_graph'}="Graph";
$LOC{'menu_view_graph.help'}='Show time/money graphs of all active peers';
$LOC{'menu_view_clock'}="Show clock";
$LOC{'menu_view_progress_bar'}="Show progress bar";
$LOC{'menu_view_stat'}="Statistic ...";
$LOC{'menu_view_stat.help'}='Show a time/money history list for this user';
$LOC{'button_main_hangup'}="Hangup";
#---- Help Menu
$LOC{'menu_help'}="Help";
$LOC{'menu_help_about'}="About ...";
$LOC{'menu_help_about.help'}='Show information about this program and its author';
$LOC{'menu_help_balloon_help'}="Mouse Pointer Help";
$LOC{'menu_help_balloon_help.help'}='Toggle showing balloon help';
#---- Rate Window
$LOC{'win_rate_date_start'}='Start Date';
$LOC{'win_rate_date_start.help'}='Date when this rate became vaild (may be empty if next field is empty too)';
$LOC{'win_rate_date_end'}='End Date';
$LOC{'win_rate_date_end.help'}='Date when this rate became or will become invalid';
$LOC{'win_rate_weekdays'}='Weekdays';
$LOC{'win_rate_weekdays.help'}='Set of numbers (0..6) representing weekdays (Sun..Sat)';
$LOC{'win_rate_daytime_start'}='Start Time';
$LOC{'win_rate_daytime_start.help'}='Daytime on which this rate becomes valid (may be empty if next field is empty too)';
$LOC{'win_rate_daytime_end'}='End Time';
$LOC{'win_rate_daytime_end.help'}='Daytime on which tis rate becomes invalid (must end before midnight!)';
$LOC{'win_rate_money_per_min'}='M/min';
$LOC{'win_rate_money_per_min.help'}='Payment in money per minute (not per unit!)'; 
$LOC{'win_rate_secs_per_unit'}='secs/unit';
$LOC{'win_rate_secs_per_unit.help'}='Length of a unit in seconds';
$LOC{'win_rate_money_per_connect'}='M/Conn.';
$LOC{'win_rate_money_per_connect.help'}='Payment per connection (usually 0)';
$LOC{'win_rate_free_linkup'}='FL';
$LOC{'win_rate_free_linkup.help'}='Free DialUp (Paying starts not before PPP connection is up)';
$LOC{'win_rate_overlay_rate'}='OR';
$LOC{'win_rate_overlay_rate.help'}='Overlay Rate (this may be a additional payment with a different unit length)';
#--- Main Window
$LOC{'win_main_start'}="Start";
$LOC{'win_main_start.help'}="Hit a Button to Connect a Peer";
$LOC{'win_main_money'}="Money";
$LOC{'win_main_money.help'}="Real Time Money Counter";
$LOC{'win_main_rate'}="Rate";
$LOC{'win_main_rate.help'}="Money per Minute";
#---

# read in locale file (see ./locale-de for a german locale file)
if (open (LOC, "$progdir/locale-$applang")) {
    my $line=0;
    while (<LOC>) {
	++$line;
	if (/^wday_names\s*=\s*(\w+)\s+(\w+)\s+(\w+)\s+(\w+)\s+(\w+)\s+(\w+)\s+(\w+)\s+$/) {
	    @wday_names=($1, $2, $3, $4, $5, $6, $7); 
	} elsif (/^([a-z_.]+)\s*=\s*(.+)\s*$/) {
	    my $key=$1;
	    my $val=$2;
	    if (defined $LOC{$key}) {
		$LOC{$key}=unescape_string($val);
	    } else {
		print STDERR "$progdir/locale-$applang:$line: Unknown configuration key <$1>\n";
	    }
	}
    }
    close LOC;
}

# open log file
if (defined $cost_out_file) {
    open (LOG, ">>$cost_out_file") or die;
    LOG->autoflush (1);
#    close LOG unless (flock (LOG, LOCK_EX | LOCK_NB));
}

## Protos
sub link_started ();
sub link_stoppend ();
sub cb_disconnect ();
sub update_sum ();
sub cfg_editor_window ($$);
sub update_state ();
sub update_sum ();
sub write_ulog ();
sub db_time ();
sub start_plog_scanner ();
sub stop_log_scanner ();
## Tk-Gui Protos
sub cb_disconnect ();
sub main_window_iconify ();
sub main_window_deiconify ();
sub update_gui_offline ();
sub update_gui_failure ();
sub update_gui_counter ();
sub clear_gui_counter ();

# misc globals
my $curr_secs_per_unit=10;
my $time_start = 0;
my $time_disconnect = 0;
my $time_dial_start = 0;
my $db_start_time = time ();

# State Transition Command Hooks
my @commands_on_startup = ();
my @commands_before_dialing = (sub { $time_dial_start = db_time(); }, \&clear_gui_counter, \&update_gui_dialing);
my @commands_on_connect = (sub { $time_start = db_time(); }, \&link_started, \&main_window_iconify, \&update_gui_online);
my @commands_on_connect_failure = (\&update_gui_failure, \&clear_gui_counter, \&link_stopped);
my @commands_on_disconnect = (sub { $time_disconnect = db_time(); }, \&main_window_deiconify, \&update_gui_offline,
    \&update_gui_counter, \&update_progress_bar, \&write_ulog, \&link_stopped);

# GUI Transition Command Hook
my @commands_on_gui_deiconify = ();
# Commands Issued Each Tick
my @commands_while_online = (\&update_sum, \&check_automatic_disconnect);


my ($state_startup, $state_offline, $state_dialing, $state_online) = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9);
my $state=$state_startup;

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
    printf STDERR "trace: %s\n", $_[0] if $db_tracing;
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
sub gui_trans_deiconify () {
    db_trace ("gui_trans_deiconify");
    foreach my $cmd (@commands_on_gui_deiconify) { &$cmd; }
}
sub state_trans_startup_to_offline () {
    db_trace ("state_trans_startup_to_offline");
    $state = $state_offline; foreach my $cmd (@commands_on_startup) { &$cmd; }
}
sub state_trans_offline_to_dialing () {
    db_trace ("state_trans_offline_to_dialing");
    $state = $state_dialing; foreach my $cmd (@commands_before_dialing) { &$cmd; }
}
sub state_trans_dialing_to_online () {
    db_trace ("state_trans_dialing_to_online");
    $state = $state_online; foreach my $cmd (@commands_on_connect) { &$cmd; }
}
sub state_trans_dialing_to_offline () {
    db_trace ("state_trans_dialing_to_offline");
    $state = $state_offline; foreach my $cmd (@commands_on_connect_failure) { &$cmd; }
}
sub state_trans_online_to_offline () {
    db_trace ("state_trans_online_to_offline");
    $state = $state_offline; foreach my $cmd (@commands_on_disconnect) { &$cmd; }
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


## Tk-GUI
use Tk;
use Tk::ROText;
use Tk::ProgressBar;
use Tk::Balloon;

sub update_gui_offline ();
sub update_gui_online ();
sub update_gui ();
sub cb_disconnect ();
sub cb_dialup2 ( $ );
sub cb_dialup ( $ );
sub make_gui_mainwindow ();

my %cfg_gui_default= (balloon_help => '1', show_rtc => '1', show_progress_bar => '1',
		      graph_bgcolor => 'Grey85', graph_nrcolor => 'Grey70', graph_ercolor => 'Grey55');
my %cfg_gui = %cfg_gui_default;
my $main_widget;
my @entries;
my %labels;
my $disconnect_button;

my %widgets;
my $rtc_widget;
my $pb_widget;
my ($offs_record, $offs_isp_widget, $offs_sum_widget, $offs_min_price_widget) = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9);


sub set_color_entry ($$) {
    my ($entry, $color) = @_;
    $entry->configure(-foreground => $color, -background => $cfg_gui{'graph_bgcolor'});
}
sub get_color_entry ( $ ) {
    my ($entry) = @_;
    $entry->cget('-foreground');
}

sub update_gui_dial_state ( $ ) {
    my ($color) = @_;
    foreach my $isp (@isps) {
	next unless (get_isp_flag_active ($isp));
	my $label =  $labels{$isp};
	if (defined $label) {
	    my $bg_color = ($isp ne $isp_curr) ? $label->parent->cget('-background') : $color;
	    $label->configure(-background => $bg_color);
	}
    }
}

sub update_gui_failure () {
    update_gui_dial_state ('Red');
}

sub update_gui_offline () {
    update_gui_dial_state ('Grey');
}

sub update_gui_online () {
    update_gui_dial_state ('Cyan');
}

sub update_gui_dialing () {
    update_gui_dial_state ('Yellow');
}


sub update_progress_bar () {
    use integer;
    my $tem = (db_time () - ($time_start - $ppp_offset)) % $curr_secs_per_unit;
    my $percent_done =  ($tem * 100) / $curr_secs_per_unit;
    $pb_widget->value($percent_done);

    no integer;
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

sub clear_gui_counter () {
    while (my ($isp, $wid) = each (%widgets)) {
	my $entry=$$wid[$offs_sum_widget];
	$entry->delete ('1.0', 'end');
	$entry->configure (-background => $entry->parent->cget('-background'));

# FIXME: move the following
	if ($state == $state_dialing and $isp eq $isp_curr) {
#	    $entry->insert('1.0', 'dialing');
	    $entry->configure (-background => 'Yellow');
	}
    }
}

sub update_gui_counter () {
    my @sums;
    my %sum_cache;

    while (my ($isp, $wid) = each (%widgets)) {
	my $sum = get_sum ($isp);
	$sums[$#sums+1] = $sum;
	$sum_cache{$isp} = $sum;
    }

    @sums = sort {$a <=> $b} @sums;
    my $cheapest = $sums[$[];
    my $most_expensive = $sums[$#sums];

    while (my ($isp, $wid) = each (%widgets)) {
	my $price = $sum_cache{$isp};
	my $entry=$$wid[$offs_sum_widget];
	$entry->delete ('1.0', 'end');
	$entry->insert('1.0', sprintf ("%4.2f Pfg", $price));
	my $bg_color = (($cheapest == $price) ? 'Green'
			: (($most_expensive == $price) ? 'OrangeRed'
			   : 'Yellow'));
	$entry->configure (-background => $bg_color);
    }
}
sub update_gui_counter_old () {
    my $cheapest=999999;
    my $most_expensive=0;

    foreach my $isp (@isps) {
	next unless (get_isp_flag_active ($isp));

	my $i = get_sum ($isp);
	$cheapest = $i if $cheapest > $i;
	$most_expensive = $i if $most_expensive < $i;
    }

    while (my ($isp, $wid) = each (%widgets)) {
	my $price = get_sum ($isp);
	my $entry=$$wid[$offs_sum_widget];
	$entry->delete ('1.0', 'end');
	$entry->insert('1.0', sprintf ("%4.2f Pfg", $price));
	my $bg_color = (($cheapest == $price) ? 'Green'
			: (($most_expensive == $price) ? 'OrangeRed'
			   : 'Yellow'));
	$entry->configure (-background => $bg_color);
    }
}

sub update_gui_pfg_per_minute ( $ ) {
    my ($curr_time)=@_;
    while (my ($isp, $wid) = each (%widgets)) {
	my $widget=$$wid[$offs_min_price_widget];
	$widget->delete ('1.0', 'end');
	$widget->insert('1.0', sprintf ("%.2f", Dialup_Cost::calc_price (get_isp_tarif($isp), $curr_time, 60)));
    }
}

sub update_gui_rtc () {
    $rtc_widget->delete ('1.0', 'end');
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime (time ());
    $rtc_widget->insert('1.0', sprintf (" %s  %u-%02u-%02u  %02u:%02u:%02u",
					$wday_names[$wday],
					$year + 1900, $mon + 1, $mday,
					$hour, $min, $sec,
					)); 
}
sub rtc_max_width () {
    my $max_wday_len=0;
    my $rtc_time_len=24;
    foreach my $wday (@wday_names) {
	if ((my $len = length ($wday)) > $max_wday_len) { $max_wday_len = $len; }
    }
    $max_wday_len + $rtc_time_len;
}

sub update_gui () {
    my $curr_time = db_time();

    if ($main_widget->state eq 'normal') {
	if ($state == $state_online or $state == $state_dialing) {
	    $disconnect_button->configure(-state => 'normal');
	} else {
	    $disconnect_button->configure(-state => 'disabled');
	}
	update_gui_counter () if ($state == $state_online);
	update_gui_pfg_per_minute ($curr_time);
	update_gui_rtc ();
	update_progress_bar () if ($state == $state_online);
    }

}

sub cb_disconnect () {
    if ($isp_curr) {
	my $cmd = get_isp_disconnect_cmd ($isp_curr);
	qx($cmd);
    }
    # remove highlight on isp labels
    foreach my $isp (@isps) {
	next unless (get_isp_flag_active ($isp));

	my $label =  $labels{$isp};
	if (defined $label) {
	    my $bg_color = ($isp ne $isp_curr) ? $label->parent->cget('-background') : 'Grey';
	    $label->configure(-background => $bg_color);
	}
    }
    0;
}


sub cb_dialup2 ( $ ) {
    my ($isp) = @_;
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

sub cb_dialup ( $ ) {
    my ($isp) = @_;
    cb_disconnect ();
    start_plog_scanner () or die "$progname: cannot start status_reader.pl";
    cb_dialup2 ($isp);
}

## display time/money graphs
sub make_diagram ( $$$$ ) {
    my ($win, $canvas, $xmax, $ymax) = @_;
    my ($width, $height) = ($canvas->width - 60, $canvas->height - 60);
    my ($xscale, $yscale) = ($width/$xmax, $height/$ymax); # convinience
    my ($xoffs, $yoffs) = (30, -30);

    $canvas->delete($canvas->find('all'));

    # print vertical diagram lines and numbers
    for (my $i=0; $i <= $xmax; $i+=60) {
	my $x = $i * $xscale + $xoffs;
	$canvas->createLine($x, -$yoffs, $x, -$yoffs + $height,
			    -fill => ($i%300) ? $cfg_gui{'graph_nrcolor'} : $cfg_gui{'graph_ercolor'});
	if (($i%300) == 0) {
	    $canvas->createText($x, $height - $yoffs + 10,
				-text => sprintf ("%u",  $i / 60));
	}
    }

    # print horizontal diagram lines and numbers
    for (my $i=0; $i <= $ymax; $i+=10) {
	my $y = -($i * $yscale + $yoffs - $height);
	$canvas->createLine($xoffs, $y, $width + $xoffs,  $y,
			    -fill => ($i%50) ? $cfg_gui{'graph_nrcolor'} : $cfg_gui{'graph_ercolor'});
	if (($i%50) == 0) {
	    $canvas->createText(10, $y, -text => sprintf ("%0.1f", $i / 100));
	}
    }

    # print labels in matching color
    if (1) {
	my $y=40;
	foreach my $isp (@isps) {
	    next unless (get_isp_flag_active ($isp));

	    $canvas->createText(40, $y,
				-text => get_isp_label($isp),
				-anchor => 'w',
				-fill => get_isp_color($isp));
	    
	    $y+=13;
	}
    }

    # print graphs in matching color
    foreach my $isp (reverse (@isps)) {
	next unless (get_isp_flag_active ($isp));
	my $time=db_time();
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
	  my @tmp =Dialup_Cost::tarif (get_isp_tarif($isp), $time + $restart_x1);
	  my $tar = $tmp[0];   # rate list
	  my $swp = $tmp[2];   # absolute switchpoints (time of changing rates)
	  my ($x, $y) = (0, 0);
	  my $is_linear=1;
	  my @data=();
	  my $next_switch=9999999999;
	  foreach my $a (@$tar) {
	      my $offs_time = $$a[$Dialup_Cost::offs_sw_start_time] * $ppp_offset;
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
		      $g[$#g+1] = $u++ * $$a[$Dialup_Cost::offs_pfg_per_clock];

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

	  $args[$#args+1] = '-fill';
	  $args[$#args+1] = get_isp_color($isp);
	  $canvas->createLine (@args);

	  if ($flag_do_restart) {
	      $restart_y = $graph[$#graph];
	      goto restart if $flag_do_restart;
	  }
      }
    }
}

sub make_gui_graphwindow ( $$ ) {
    my ($xmax, $ymax) = @_; #(30 * $secs_per_min, 200);
    my ($width, $height) = (500, 350);
    my ($xscale, $yscale) = ($width/$xmax, $height/$ymax); # convinience
    my ($xoffs, $yoffs) = (20, -20);
    my $win=$main_widget->Toplevel;
    $win->title("$APPNAME: Graph");
    my $canvas=$win->Canvas(-width => $width + 40, -height => $height + 40, -background => $cfg_gui{'graph_bgcolor'});
    $canvas->pack(-expand => 1, -fill => 'both');
    $canvas->Tk::bind('<Configure>' => sub { make_diagram ($win, $canvas, $xmax, $ymax) });
}

## display about window
sub make_gui_aboutwindow () {
    my $win=$main_widget->Toplevel;
    my ($width, $height) = (200, 200);

    my ($about_txt, $about_lines, $about_columns) = ("", 0, 0);
    if (open (ABT, "$progdir/about-$applang")) {
	while (<ABT>) {
	    $about_txt .= $_;
	    $about_lines++;
	    my $len = length($_);
	    $about_columns = $len if ($len > $about_columns);
	}
	close (ABT);
    }
    chomp $about_txt;

    $win->title("$APPNAME: About");
    my $txt = $win->ROText(-height => $about_lines,
			   -width => $about_columns,
			   -wrap => 'none'
			   );
    $txt->pack();
    $txt->insert('end', $about_txt);

}

## display money and time statisctics from user owned logfile
sub make_gui_statwindow () {
    my $win=$main_widget->Toplevel;
    my ($width, $height) = (200, 200);

    my ($stat_txt, $stat_lines, $stat_columns) = ("", 0, 0);
    if (open (STA, "$progdir/stat_new.pl < $cost_out_file |")) {
	while (<STA>) {
	    $stat_txt .= $_;
	    $stat_lines++;
	    my $len = length($_);
	    $stat_columns = $len if ($len > $stat_columns);
	}
	close (STA);
    }
    chomp $stat_txt;

    $win->title("$APPNAME: Stat");
    my $txt = $win->ROText(-height => $stat_lines,
			   -width => $stat_columns,
			   -wrap => 'none'
			   );
    $txt->pack();
    $txt->insert('end', $stat_txt);
}

sub make_gui_mainwindow () {
    $main_widget = MainWindow->new;
    $main_widget->title("$APPNAME");
    $main_widget->resizable (0, 0);
    my $balloon = $main_widget->Balloon();
    #### Menu ####
    my $menubar = $main_widget->Frame (-relief => 'raised');
    my $file_menu_bt = $menubar->Menubutton (-text => $LOC{'menu_file'});
    my $file_menu = $file_menu_bt->Menu();
    $file_menu_bt->configure (-menu => $file_menu);
    my $edit_menu_bt = $menubar->Menubutton (-text => $LOC{'menu_edit'});
    my $edit_menu = $edit_menu_bt->Menu();
    $edit_menu_bt->configure (-menu => $edit_menu);
    my $view_menu_bt = $menubar->Menubutton (-text => $LOC{'menu_view'});
    my $view_menu = $view_menu_bt->Menu();
    $view_menu_bt->configure (-menu => $view_menu);
    my $help_menu_bt = $menubar->Menubutton (-text => $LOC{'menu_help'});
    my $help_menu = $help_menu_bt->Menu();
    $help_menu_bt->configure (-menu => $help_menu);

#    $file_menu->command (-label => 'Speichern');
    $file_menu->command (-label => $LOC{'menu_file_hangup_now'}, -command => sub { cb_disconnect () });
    $file_menu->add ('checkbutton',
		     -label =>  $LOC{'menu_file_hangup_defer'},
		     -variable => \$flag_stop_defer);
		    

    $file_menu->command (-label => $LOC{'menu_file_save'}, -command => sub { write_config($cfg_file_usr); });
    $file_menu->command (-label => $LOC{'menu_file_quit'}, -command => sub { cb_disconnect () ; exit });

    $edit_menu->command (-label => $LOC{'menu_edit_peer_options'}, -command => sub { cfg_editor_window (100,200) });
    $edit_menu->command (-label => $LOC{'menu_edit_graph_options'}, -command => sub { color_cfg_editor_window (100,200) });

    $view_menu->command (-label => "$LOC{'menu_view_graph'} 5 min ...", -command => sub {make_gui_graphwindow(5 * $secs_per_min, 50) });
    $view_menu->command (-label => "$LOC{'menu_view_graph'} 15 min ...", -command => sub {make_gui_graphwindow(15 * $secs_per_min, 100) });
    $view_menu->command (-label => "$LOC{'menu_view_graph'} 30 min ...", -command => sub {make_gui_graphwindow(30 * $secs_per_min, 200) });
    $view_menu->command (-label => "$LOC{'menu_view_graph'} 1 h ...", -command => sub {make_gui_graphwindow(1 * $secs_per_hour, 400) });
#    $view_menu->command (-label => "$LOC{'menu_view_graph'} 2 h ...", -command => sub {make_gui_graphwindow(2 * $secs_per_hour, 800) });
    $view_menu->add ('separator');
    $view_menu->command (-label => $LOC{'menu_view_stat'}, -command => sub {make_gui_statwindow() });
    $view_menu->add ('separator');
    $view_menu->add ('checkbutton', -label => $LOC{'menu_view_clock'},
		     -variable => \$cfg_gui{'show_rtc'},
		     -command => sub { if (!defined $rtc_widget->manager) { $rtc_widget->pack(-side => 'top'); }
				       else { $rtc_widget->packForget(); } });

    $view_menu->add ('checkbutton', -label => $LOC{'menu_view_progress_bar'},
		     -variable => \$cfg_gui{'show_progress_bar'},
		     -command => sub { if (!defined $pb_widget->manager) {
			                  $pb_widget->pack(-expand => 1, -fill => 'x');
				       } else { $pb_widget->packForget(); } });

    $help_menu->add ('checkbutton', -label => $LOC{'menu_help_balloon_help'},
		     -variable => \$cfg_gui{'balloon_help'},
		     -command => sub {
			 $balloon->configure(-state => ($cfg_gui{'balloon_help'} ? 'balloon' : 'none')); });
    $balloon->configure(-state => ($cfg_gui{'balloon_help'} ? 'balloon' : 'none'));

    $help_menu->add ('separator');
    $help_menu->command (-label => $LOC{'menu_help_about'}, -command => sub {make_gui_aboutwindow() });

    $balloon->attach($file_menu,
		     -state => 'balloon',
		     -msg => ['',
			      $LOC{'menu_file_hangup_now.help'},
			      $LOC{'menu_file_hangup_defer.help'},
			      $LOC{'menu_file_save.help'},
			      $LOC{'menu_file_quit.help'},
			      ],
                     );
    $balloon->attach($edit_menu,
		     -state => 'balloon',
		     -msg => ['',
			      $LOC{'menu_edit_peer_options.help'},
			      $LOC{'menu_edit_graph_options.help'},
			      $LOC{'menu_edit_options.help'},
			      ],
                     );
    $balloon->attach($view_menu,
		     -state => 'balloon',
		     -msg => ['',
			      $LOC{'menu_view_graph.help'},
			      $LOC{'menu_view_graph.help'},
			      $LOC{'menu_view_graph.help'},
			      $LOC{'menu_view_graph.help'},
			      '',
			      $LOC{'menu_view_stat.help'},
			      '',
			      'Enable/disable a digital clock',
			      ],);

    $balloon->attach($help_menu,
		     -state => 'balloon',
		     -msg => ['',
			      $LOC{'menu_help_balloon_help.help'},
			      '',
			      $LOC{'menu_help_about.help'},
			      ],
                     );

    $menubar->pack(-expand => 1, -fill => 'x');
    $file_menu_bt->pack(-side => 'left');
    $edit_menu_bt->pack(-side => 'left');
    $view_menu_bt->pack(-side => 'left');
    $help_menu_bt->pack(-side => 'right');

    #### RTC ####
    my $rtc_frame = $main_widget->Frame;
    $rtc_widget = $rtc_frame->ROText(-height => 1, -width => rtc_max_width (), -takefocus => 0, -insertofftime => 0);

    $rtc_frame->pack(-expand => 1, -fill => 'both' );
    $rtc_widget->pack(-expand => 1, -fill => 'x') if $cfg_gui{'show_rtc'};

    #### Controls ####
	my $button_frame = $main_widget->Frame;
    {
	my $row=0;
	my $usepack=0;

	unless ($usepack) {
	    my $label;
	    $label=$button_frame->Label(-text => $LOC{'win_main_start'})->grid(-row => $row, -column => 0);
	    $balloon->attach($label, -balloonmsg => $LOC{'win_main_start.help'}) if $balloon;
	    $label=$button_frame->Label(-text => $LOC{'win_main_money'})->grid(-row => $row, -column => 1);
	    $balloon->attach($label, -balloonmsg => $LOC{'win_main_money.help'}) if $balloon;
	    $label=$button_frame->Label(-text => $LOC{'win_main_rate'})->grid(-row => $row, -column => 2);
	    $balloon->attach($label, -balloonmsg => $LOC{'win_main_rate.help'}) if $balloon;
	    $row++;
	}
	foreach my $isp (@isps) {
	    next unless (get_isp_flag_active ($isp));
	    my $frame = $usepack ? $button_frame->Frame : $button_frame;
		
	    my $cmd_button = $frame->Button(-text => get_isp_label ($isp),
				       -command => sub{ cb_dialup ($isp) } );
	    my $text = $frame->ROText(-height => 1, -width => 10, -takefocus => 0, -insertofftime => 0);
	    my $min_price = $frame->ROText(-height => 1, -width => 5, -takefocus => 0, -insertofftime => 0);

	    $cmd_button->configure(-background => 'Cyan') if ($isp eq $isp_curr);

	    if ($usepack) {
		$cmd_button->pack(-expand => 1, -fill => 'x', -side => 'left');
		$min_price->pack(-side => 'right');
		$text->pack(-side => 'right');
		$frame->pack(-expand => 1, -fill => 'x');
	    } else {
		$cmd_button->grid(-column => 0, -row => $row, -sticky => "ew");
		$text->grid(-column => 1, -row => $row, -sticky => "ew");
		$min_price->grid(-column => 2, -row => $row, -sticky => "ew");
	    }
	    $entries[$#entries+1] = $text;
	    $labels{$isp} = $cmd_button;
	    $widgets{$isp} = [0, $cmd_button, $text, $min_price];
	    $row++;
	}
	    $button_frame->pack(-expand => 1, -fill => 'x');
    }
    my @tmp = $button_frame->gridBbox;
    db_trace ("@tmp");

    #### Progress Bar ####
    {
	my $pb_frame=$main_widget->Frame();
	my $pb = $pb_frame->ProgressBar
	    (
#	     -length => 220,
	     -width => 8,
	     -from => 100,
	     -to => 0,
	     -blocks => 10,
	     -colors => [0, 'green', 50, 'yellow' , 80, 'red'],
#	     -variable => \$percent_done,
#	     -relief => 'sunken',
	     -pady => 1,
	     -padx => 1,
	     );
	$pb->pack(-expand => 1, -fill => 'x') if $cfg_gui{'show_progress_bar'};
	$pb_widget = $pb;
	$pb_frame->pack(-expand => 1, -fill => 'x');
    }
    {
	my $frame = $main_widget->Frame;
	my $b1 = $frame->Button(-text => "$LOC{'button_main_hangup'}", -command => sub{cb_disconnect});
	$balloon->attach($b1, -balloonmsg => 'Disconnect immediatly by issuing "Down Cmd"') if $balloon;
	my $b2 = $frame->Button(-text => 'Graph', -command => sub{make_gui_graphwindow(30 * $secs_per_min, 200)});
	my $b3 = $frame->Button(-text => 'Exp-Graph', -command => sub{exp_make_gui_graphwindow()});
	
	$b1->pack(-expand => 1, -fill => 'x', -side => 'left');
#	$b2->pack(-expand => 1, -fill => 'x',  -side => 'left');
#	$b3->pack(-expand => 1, -fill => 'x',  -side => 'left') if defined &exp_make_gui_graphwindow;
	$frame->pack(-expand => 1, -fill => 'x');
	$disconnect_button=$b1;
    }
    $main_widget->repeat (1000, sub{update_gui()});
    $main_widget->repeat (1000, sub{tick()});


    if ($state == $state_startup) {
	state_trans_startup_to_offline ();
   }
    if ($db_ready) {
	state_trans_offline_to_dialing ();
#	state_trans_dialing_to_online ();
    }
}

sub main_window_iconify () {
    $main_widget->iconify;
}

sub main_window_deiconify () {
    $main_widget->deiconify;
    gui_trans_deiconify ();
}

# configuration
sub read_config_old ($) {
    my ($file) =@_;
    my $mi = '\'([^\']*)\'';
    my $match_line = "$mi, +$mi, +$mi, +$mi, +$mi, +$mi, +$mi, *";
    if (open IN, ($file)) {
	while (<IN>) {
	    if (/^#/) {
		next;
	    } elsif (/$match_line/) {
		$isps[$#isps+1]=$1;
		set_isp_cfg ([$1, $2, $3, $4, $5, $6, $7]);
	    }
	}
	close IN;
	1;
    } else {
	0;
    }
}

sub write_config_old ($) {
    my ($file) =@_;
    if (open OUT, (">$file")) {
	my $fi = '\'%s\'';
	my $fmt_line = "$fi, $fi, $fi, $fi, $fi, $fi, $fi, \n";
	foreach my $isp (@isps) {
	    printf OUT $fmt_line,
	    $isp,
	    get_isp_cmd($isp),
	    get_isp_disconnect_cmd($isp),
	    get_isp_label($isp),
	    get_isp_color($isp),
	    get_isp_tarif($isp),
	    get_isp_flag_active($isp);
	}
	close OUT;
	1;
    } else {
	0;
    }
}
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
			$cfg_gui{"$key"} = $val;
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
	foreach my $isp (@isps) {
	    printf OUT ($fmt_line,
			$cfg_att_names[$cfg_isp], escape_string ($isp),
			$cfg_att_names[$cfg_cmd], escape_string (get_isp_cmd($isp)),
			$cfg_att_names[$cfg_disconnect_cmd], escape_string (get_isp_disconnect_cmd($isp)),
			$cfg_att_names[$cfg_label], escape_string (get_isp_label($isp)),
			$cfg_att_names[$cfg_color], escape_string (get_isp_color($isp)),
			$cfg_att_names[$cfg_tarif], escape_string (get_isp_tarif($isp)),
			$cfg_att_names[$cfg_active], escape_string (get_isp_flag_active($isp)));

	}
	{
	    my $line="";
	    my $count=0;
	    while (my ($key, $val) = each (%cfg_gui)) {
		if ("$cfg_gui_default{$key}" ne $val) {
		    $line .= "$key='" . escape_string ($val) . "' ";
		    db_trace ("key=<$key> val=<$val> count=<$count>");
		}
	    }
	    if ($line) {
		print OUT '<gui ' . $line . "/>\n";
	    }
	}
	close OUT;
	1;
    } else {
	0;
    }
}

# config editor gui
=pod

=head2 NAME

mask_widget() - produce pairs of key/value-widgets

=head2 PARAMETERS and RESULT

=over 4

=item MASK_FRAME - Created widgets will be direct childs of it

=item ROW - Row on which our first new produced widget pair starts.

=item WIDGETS - Array to keep produced value widgets (Entry, Checkbox)

=item TYPES - Array holding type info strings ('text', 'flag', 'color', 'label')

=item KEYS - Array holding key strings (using for label names)

=item VALOC - Array holding value strings (will be used as defaults on value widgets)

=item RESULT - row-number after our last produced widget

=back


=head2 DESCRIPTION

=cut

sub mask_widget ($$$$$$) {
    my ($mask_frame, $row, $widgets, $types, $keys, $vals) = @_;
    for my $i (0..$#$keys) {
	my ($key, $val) = ($$keys[$i], $$vals[$i]);
	$val="" unless defined $val;
	db_trace("row:$row");
	$mask_frame->Label(-text => "$key")->grid(-row => $row, -column => 0, -sticky => "e");
	if ($$types[$i] eq 'text') {
	    my $entry = $mask_frame->Entry()->grid(-row => $row, -column => 1);
	    $entry->insert(0, $val);
	    $$widgets[$i] = $entry;
	} elsif ($$types[$i] eq 'flag') {
	    my $cb = $mask_frame->Checkbutton()->grid(-row => $row, -column => 1, -sticky => "w");
	    $cb->select if ($val == '1');
	    $$widgets[$i] = $cb;
	} elsif ($$types[$i] eq 'label') {
	    my $label = $mask_frame->Label(-text => "$val")->grid(-row => $row, -column => 1, -sticky => "w");
	    $$widgets[$i] = $label;
	} elsif ($$types[$i] eq 'color') {
	    my $entry = $mask_frame->Entry()->grid(-row => $row, -column => 1);
	    set_color_entry ($entry, $val);

	    $entry->insert(0, $val);
	    $$widgets[$i] = $entry;
	    $mask_frame->Button
		(-text => "$key", -command => sub
		 {
		     my $old_color = get_color_entry ($entry);
		     my $color = $mask_frame->chooseColor(-parent => $mask_frame,
							  -initialcolor => "$old_color");
		     if ($color) {
			 $entry->delete(0, 'end');
			 $entry->insert(0, "$color");
			 set_color_entry ($entry, $color);
		     }
		 } )->grid(-row => $row, -column => 0, -sticky => "ew");

	    # Toggling color preview in Entry widget using MousePress events
	    my ($sub_preview_on, $sub_preview_off);
	    $sub_preview_on = sub {
		set_color_entry ($entry, $entry->get());
		$entry->Tk::bind ('<ButtonPress>', $sub_preview_off);
	    };
	    $sub_preview_off = sub {
		$entry->configure (-fg => $mask_frame->cget('-fg'),
				   -bg => $mask_frame->cget('-bg'));
		$entry->Tk::bind ('<ButtonPress>', $sub_preview_on);
	    };
	    $entry->Tk::bind ('<ButtonPress>', $sub_preview_off);
	}
	$row++;
    }

    $mask_frame->pack(-side => 'top');
    db_trace ("gridSize: " . $mask_frame->gridSize);
    $row;
}

my @cfg__isp_cfg_cache;
sub edit_bt_ok($$$$) {
    my ($frame, $lb, $index, $widgets) = @_;
    my @config_values;

    # copy values from widgets to array @config_values
    foreach my $i (0..$#$widgets) {
	if ($cfg_types[$i] eq 'text') {
	    $config_values[$#config_values+1] = $$widgets[$i]->get;
	} elsif ($cfg_types[$i] eq 'color') {
	    $config_values[$#config_values+1] = $$widgets[$i]->get;
	    set_color_entry ($$widgets[$i], $$widgets[$i]->get);
	} elsif ($cfg_types[$i] eq 'flag') {
	    $config_values[$#config_values+1] = $$widgets[$i]->{'Value'};
	}
    }

    # update (overwrite) global configuration for this ISP
    # (widgets are currently in same order as global ISP config table is
    #  so we can just pass our value array to set_isp_cfg())
    set_isp_cfg (\@config_values);

    # update our configuration cache to reflect change in global configuration made above
    my $isp = $config_values[0];
    foreach my $i (0..$#cfg__isp_cfg_cache) {
	my $r = $cfg__isp_cfg_cache[$i];
	if ($$r[$cfg_isp] eq $isp) {
	    $cfg__isp_cfg_cache[$i] = \@config_values;
	}
    }
}

# TODO: TAB switching order
sub cost_mask_window ($$$$) {
    my ($parent, $matrix, $entries, $balloon) = @_;
    my $labels=$$matrix[0];
    my $balloons=$$matrix[2];
    my $fmts=$$matrix[1];
    my $start_matrix=3;
    my $rows = scalar @$matrix - $start_matrix;
    my $cols = scalar @$labels;
    my $top = $parent->Frame;
    my $table_frame = $top->Frame;
    $table_frame->pack(-side => 'top');
    ## make table columns
    for (my $c=0; $c < $cols; $c++) {
	my @wids;
	# make column label (table head)
	my $label = $table_frame->Label(-text => $$labels[$c])->grid(-row => 0, -column => $c);
	# atach balloon help to table head
	$balloon->attach($label, -balloonmsg => $$balloons[$c]) if $balloon && $$balloons[$c];
	# make column cells
	foreach my $r ($start_matrix..$#$matrix) {
	    if ($$fmts[$c] =~ /^cstring:(\d+)/) {
		my $width=$1;
		my $wid = $table_frame->Entry(-width => $width);
		my $col_matrix= $$matrix[$r];
		# insert data from COL_MATRIX
		$wid->insert(0, $$col_matrix[$c]);
#		$balloon->attach($wid, -balloonmsg => $$balloons[$c]) if $balloon && $$balloons[$c];
		$wid->grid(-row => $r, -column => $c);
		$wids[$#wids+1] = $wid;
	    } elsif (($$fmts[$c] =~ /^checkbox$/)) {
		my $wid = $table_frame->Checkbutton();
		my $col_matrix= $$matrix[$r];
		$wid->select if $$col_matrix[$c];
#		$balloon->attach($wid, -balloonmsg => $$balloons[$c]) if $balloon && $$balloons[$c];
		$wid->grid(-row => $r, -column => $c);
	    }
	}
	$$entries[$#$entries+1]=\@wids;
    }
    my $button_frame = $top->Frame;
    $button_frame->pack(-side => 'bottom');
    foreach my $lab (('Append Row', 'Insert Row', 'Remove Row')) {
	my $wid = $button_frame->Button (-text => $lab, -state => 'disabled');
	$wid->pack (-side => 'left');
    }
    $top;
}
sub cost_mask_window_old ($$$) {
    my ($parent, $matrix, $entries) = @_;
    my $labels=$$matrix[0];
    my $fmts=$$matrix[1];
    my ($rows, $cols) = ($#$matrix-1, $#$labels+1);
    my $top = $parent->Frame;
    my $table_frame = $top->Frame;
    $table_frame->pack(-side => 'top');
    for (my $c=0; $c < $cols; $c++) {
	my $frame=$table_frame->Frame;
	my @wids;
	$frame->Label(-text => $$labels[$c])->pack(-side => 'top');
	for (my $r=2; $r < $rows+2; $r++) {
	    if ($$fmts[$c] =~ /cstring:(\d+)/) {
		my $width=$1;
		my $wid = $frame->Entry(-width => $width);
		my $col_matrix= $$matrix[$r];
		$wid->insert(0, $$col_matrix[$c]);
		$wid->pack(-side => 'bottom',
			   -expand => 1,
			   -fill => 'x');
		$wids[$#wids+1] = $wid;
	    }
	}
	$frame->pack(-expand => 1, -fill => 'x', -side => 'left');
	$$entries[$#$entries+1]=\@wids;
    }
    my $button_frame = $top->Frame;
    $button_frame->pack(-side => 'bottom');
    foreach my $lab (('Append Row', 'Insert Row', 'Remove Row')) {
	my $wid = $button_frame->Button (-text => $lab);
	$wid->pack (-side => 'left');
    }
    $top;
}
## create data table for cost preferece window (cost_mask_window())
## 1st row are labels.  2nd row are data-type-IDs.  In 3rd row starts data.
sub cost_mask_data ($) {
    my ($rate_name) = @_;
    my @labels = ($LOC{'win_rate_date_start'},
		  $LOC{'win_rate_date_end'},
		  $LOC{'win_rate_weekdays'},
		  $LOC{'win_rate_daytime_start'},
		  $LOC{'win_rate_daytime_end'},
		  $LOC{'win_rate_money_per_min'},
		  $LOC{'win_rate_secs_per_unit'},
		  $LOC{'win_rate_money_per_connect'},
		  $LOC{'win_rate_free_linkup'},
		  $LOC{'win_rate_overlay_rate'},
		  );
    my @balloons = ($LOC{'win_rate_date_start.help'},
		    $LOC{'win_rate_date_end.help'},
		    $LOC{'win_rate_weekdays.help'},
		    $LOC{'win_rate_daytime_start.help'},
		    $LOC{'win_rate_daytime_end.help'},
		    $LOC{'win_rate_money_per_min.help'},
		    $LOC{'win_rate_secs_per_unit.help'},
		    $LOC{'win_rate_money_per_connect.help'},
		    $LOC{'win_rate_free_linkup.help'},
		    $LOC{'win_rate_overlay_rate.help'},
		    );
    my @matrix;
    $matrix[$#matrix+1] = \@labels;
    $matrix[$#matrix+1] = ['cstring:10','cstring:10','cstring:10','cstring:10',
			   'cstring:10','cstring:5','cstring:4','cstring:4', 'checkbox', 'checkbox'];
    $matrix[$#matrix+1] = \@balloons;
    my $rate = Dialup_Cost::get_rate ($rate_name);
    foreach my $r (@$rate) {
	my @sub_entries = ("","","","","","","","");
	my $r0 = $$r[0];

	if (ref $$r0[0]) {
	    my $r00 = $$r0[0];
	    $sub_entries[0] = ($$r00[0] == 0) ? "0" : substr (format_ltime ($$r00[0]), 0, 19);
	    $sub_entries[1] = ($$r00[1] == 0) ? "0" : substr (format_ltime ($$r00[1]), 0, 19);
	}
	if (ref $$r0[1]) {
	    my $r01 = $$r0[1];
	    foreach my $wday (@$r01) {
		$sub_entries[2] .= "$wday";
	    }
	}
	if (ref $$r0[2]) {
	    my $r02 = $$r0[2];
	    $sub_entries[3] = format_day_time ($$r02[0]);
	    $sub_entries[4] = format_day_time ($$r02[1]);
	}
	my $r1 = $$r[1];
	$sub_entries[5] = sprintf ("%.2f", ($$r1[0] * 60) / $$r1[1]);
	$sub_entries[6] = $$r1[1];
	$sub_entries[7] = $$r1[3];
	$sub_entries[8] = ($$r1[2] == 0);
	$sub_entries[9] = ($$r1[4] == 2);

	$matrix[$#matrix+1]=\@sub_entries;
    }
    parse_cost_mask_data (\@matrix);
    \@matrix;
}

sub parse_cost_mask_data ($) {
    my ($matrix) = @_;
    my @result;
    my $row_idx=-3;
    foreach my $r (@$matrix) {
	next if $row_idx++ < 0; # skip header and type-definition
	my @res_cond=(0, 0, 0);

	if ($$r[0] ne "") {
	    my $start = ($$r[0] eq "0") ? 0 : parse_ltime ($$r[0]);
	    my $end = ($$r[1] eq "0") ? 0 : parse_ltime ($$r[1]);
	    db_trace ("start: $start end: $end");
	    $res_cond[0] = [ $start, $end ];
	}
	if ($$r[2] ne "") {
	    my $str = $$r[2];
	    my @wdays;
	    while ($str =~ /([0-6])/g) {
		$wdays[$#wdays+1]= $1 * 1;
	    }
	    db_trace ("wdays: @wdays");
	    $res_cond[1] = \@wdays;
	}
	if ($$r[3] ne "") {
	    my $start_time = parse_day_time ($$r[3]);
	    my $end_time = parse_day_time ($$r[4]);
	    db_trace ("start_time: $start_time end_time: $end_time");
	    $res_cond[2] = [ $start_time, $end_time ];
	}

	my $pfg_per_connect = $$r[7] * 1;
	my $secs_per_unit = $$r[6] * 1;
	my $pfg_per_unit = ($$r[5] / 60) * $secs_per_unit;
	my $f1 = $$r[8] == 0;
	my $f2 = ($$r[9] == 1) ? 2 : 1;

	db_trace ("pfg_per_unit: $pfg_per_unit  secs_per_unit: $secs_per_unit  pfg_per_connect: $pfg_per_connect");
	my @res = ( \@res_cond, [ $pfg_per_unit, $secs_per_unit, $f1, $pfg_per_connect, $f2 ] );
	$result[$#result+1]=\@res;
#test#	print STDERR Dialup_Cost::write_list (\@res); 
    }
#test# my %tmp=(xxx => \@result); print STDERR Dialup_Cost::write_data2 (\%tmp); 
    \@result;
}

sub save_bt ( $$ ) {
    my ($lb, $cfg_file) = @_;
    write_config($cfg_file) or die;
}

sub item_edit_bt($$) {
    my ($lb, $index) = @_;
    my @entries;

    my $win = $main_widget->Toplevel;
    my $balloon = $win->Balloon();
    my $isp = $lb->get($index);
    my $isp_rate = get_isp_tarif ($isp);
    $win->title("$APPNAME: cost for rate <$isp_rate>");
    cost_mask_window ($win, cost_mask_data ($isp_rate), \@entries, $balloon)->pack();
};

sub cfg_update_gadgets ($$) {
    my ($idx, $gadgets) = @_;
    my $cfg = $cfg__isp_cfg_cache[$idx];
    for (my $i=0; $i < $cfg_SIZE; $i++) {
#	$$cfg[$i]=$$gadgets[$i]->get();
	if ($cfg_types[$i] eq 'text') {
	    $$gadgets[$i]->delete(0, 'end');
	    $$gadgets[$i]->insert(0, $$cfg[$i]);
	} elsif ($cfg_types[$i] eq 'color') {
	    $$gadgets[$i]->delete(0, 'end');
	    $$gadgets[$i]->insert(0, $$cfg[$i]);
	    set_color_entry ($$gadgets[$i], $$cfg[$i]);
	} elsif ($cfg_types[$i] eq 'flag') {
	    if ($$cfg[$i]) { $$gadgets[$i]->select; } else { $$gadgets[$i]->deselect; }
	}
    }
}

sub cfg_editor_window ($$) {
    my ($xmax, $ymax) = @_;	#(30 * $secs_per_min, 200);
    my $win=$main_widget->Toplevel;
    $win->title("$APPNAME: Config");

    my $frame1 = $win->Frame;
    my $box = $frame1->Listbox(-relief => 'sunken',
			       -width => -1, # Shrink to fit
			       -height => 10,	
			       -selectmode => 'browse',
			       -setgrid => 1);

    my $scroll = $frame1->Scrollbar(-command => ['yview', $box]);
    my $item_entry = $win->Entry();

    my $frame3 = $win->Frame;
    my $item_del_bt = $frame3->Button(-text => 'Delete', -command => sub{item_del_bt($box)});
    my $edit_bt = $frame3->Button(-text => 'Edit Rate', -command => sub{item_edit_bt($box, $box->index('active'))});
    my $item_add_bt = $frame3->Button(-text => 'Add', -command => sub{item_add_bt($box)});
#my $view_bt = $frame3->Button(-text => 'View', -command => sub{view_bt($box)});

    my $frame2 = $win->Frame;
    my $exit_bt = $frame2->Button(-text => 'Close',
				  -command => sub { undef @cfg__isp_cfg_cache; $win->destroy() });
#    my $exit_bt = $frame2->Button(-text => 'Cancel', -command => sub{ $frame2->chooseColor();});
    my $save_bt = $frame2->Button(-text => 'Save',
				  -command => sub{ save_bt($box, $cfg_file_usr);
						   undef @cfg__isp_cfg_cache;
						   $win->destroy() });

    foreach (@isps) {
	$box->insert('end', $_);
	my @cfg;
	$cfg__isp_cfg_cache[$#cfg__isp_cfg_cache+1] = \@cfg;
	for (my $i=0; $i < $cfg_SIZE; $i++) {
	    $cfg[$#cfg+1] =  get_isp_cfg ($_, $i);
	}
    }

    $box->configure(-yscrollcommand => ['set', $scroll]);

    $frame1->pack(-fill => 'both', -expand => 1);
    $box->pack(-side => 'left', -fill => 'both', -expand => 1);
    $scroll->pack(-side => 'right', -fill => 'y');
#$item_entry->pack(-fill => 'x');

    {
	my $isp = $box->get(0);
	my $top = $win->Frame;
	mask_widget ($top->Frame, 0, \@entries, \@cfg_types, \@cfg_labels, $isp_cfg_map{$isp});
#exp#	$entries[0]->configure(-invcmd => 'bell', -vcmd => sub { 0; }, -validate => 'focusout');
	my $frame1 = $top->Frame;
	$frame1->Button(-text => 'Cancel', -command => sub{edit_bt_cancel($top)})->pack(-side => 'left');
	$frame1->Button(-text => 'Apply', -command => sub{edit_bt_ok($top, $box, 0, \@entries)})->pack(-side => 'right');
	$frame1->pack(-fill => 'x');
	$top->pack(-expand => 1, -fill => 'both');
    }

    $frame3->pack(-fill => 'x');
#$view_bt->pack(-side => 'bottom');
    $item_add_bt->pack(-side => 'right');
    $item_del_bt->pack(-side => 'left');
    $edit_bt->pack();

    $frame2->pack(-fill => 'x');
    $save_bt->pack(-side => 'right');
    $exit_bt->pack(-side => 'left');

    $box->Tk::bind ('<ButtonRelease>', sub { cfg_update_gadgets ($box->index('active'), \@entries) });
}

sub color_cfg_editor_window ($$) {
    my ($xmax, $ymax) = @_;	#(30 * $secs_per_min, 200);
    my $win=$main_widget->Toplevel;
    $win->title("$APPNAME: Graph Colors");

    my @widgets;
    my @types = ('color', 'color', 'color');
    my @keys = ('Background Color', 'Ruler Color', 'Ruler2 Color');
    my @cfg_keys = ('graph_bgcolor', 'graph_nrcolor', 'graph_ercolor');
    my @vals;
    my @refs;
    my @defaults;
    foreach my $i (0..$#cfg_keys) {
	if (defined $cfg_gui{$cfg_keys[$i]}) {
	    $vals[$i] = $cfg_gui{$cfg_keys[$i]};
	    $refs[$i] = \$cfg_gui{$cfg_keys[$i]};
	    $defaults[$i] = $cfg_gui_default{$cfg_keys[$i]};
	}
    }
    my $top = $win->Frame;
    my $mask_frame = $top->Frame;
    mask_widget ($mask_frame, 0, \@widgets, \@types, \@keys, \@vals);
    $mask_frame->pack(-expand => 1, -fill => 'both');

    my $frame1 = $top->Frame;
    $frame1->Button(-text => 'Cancel', -command => sub { $win->destroy(); })->pack(-side => 'left' );
    $frame1->Button(-text => 'Apply',
		    -command => sub
		    { foreach my $i (0...$#refs) {
			if ($types[$i] eq 'color' or $types[$i] eq 'text') {
			    my $ref = $refs[$i]; 
			    $$ref = $widgets[$i]->get();
			    if ($types[$i] eq 'color') {
				set_color_entry ($widgets[$i], $widgets[$i]->get());
			    }
			}
		    }
		      $win->destroy ();
		    })->pack(-side => 'right');
    $frame1->Button(-text => 'Default',
		    -command => sub
		    { foreach my $i (0..$#cfg_keys) {
			my $ref = $refs[$i];
			my $val = $defaults[$i];
			my $wid = $widgets[$i];
			#$$ref = $val;
			if ($types[$i] eq 'color' or $types[$i] eq 'text') {
			    $wid->delete(0, 'end');
			    $wid->insert(0, "$val");
			    if ($types[$i] eq 'color') {
				set_color_entry ($wid, $val);
			    }
			}
		    }
		  })->pack();
    $frame1->pack(-fill => 'x');
    $top->pack(-expand => 1, -fill => 'both');
}

########################################################################################

read_config((-e $cfg_file_usr) ? $cfg_file_usr : $cfg_file) or die;
Dialup_Cost::read_data((-e $cost_file_usr) ? $cost_file_usr : $cost_file);

db_trace("LOC hash: " . scalar %LOC);
db_trace("cfg_gui hash: " . scalar %cfg_gui );

make_gui_mainwindow();

MainLoop;
