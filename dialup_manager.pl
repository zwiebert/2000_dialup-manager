#! /usr/local/bin/perl -w

$0 =~ m!^(.*)/([^/]*)$!;
my ($progdir, $progname) = ($1, $2);
my @isps = ("KNUUT", "KNUUT_MCI", "KNUUT_0800", "NIKOMA", "NGI", "NGI_SH", "COMUNDO", "COMUNDO_030", "DELLNET"); 
my $ppp_offset=30;
my $db_ready = 0;
my $isp_curr= defined $ARGV[0] ? $ARGV[0] : '';

use strict;
use Time::Local;
use Graphs;

sub tarif ( $$ );
sub calc_price ( $$$ );
sub init ();
sub cb_disconnect ();
sub online ();
sub check_online ();
sub update_sum ();

#-- begin library
my $days_per_week = 7;
my $hours_per_day = 24;
my $mins_per_hour = 60;
my $mins_per_day = $mins_per_hour * $hours_per_day;
my $secs_per_min = 60;
my $secs_per_hour = $secs_per_min * $mins_per_hour;
my $secs_per_day = $secs_per_hour * $hours_per_day;

my ($offs_pfg_per_clock, $offs_secs_per_clock, $offs_sw_start_time, $offs_pfg_per_connection, $offs_rate_id) = (0,1,2,3,4,5,6,7,8,9);

my %month_map=(Jan => 0, Feb => 1, Mar => 2, Apr => 3, May => 4, Jun => 5,
	       Jul => 6, Aug => 7, Sep => 8, Oct => 9, Nov => 10, Dec => 11);
my @wday_names=('Sonntag', 'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag');
my $start_sel530_knuut = timelocal(0, 0, 0, 8, $month_map{'Oct'}, 99);
my $start_knuut_mci2 = timelocal(0, 0, 0, 1, $month_map{'Nov'}, 99);
my $start_knuut_08002 = timelocal(0, 0, 0, 1, $month_map{'Nov'}, 99);
my $start_nikoma2 = timelocal(0, 0, 0, 1, $month_map{'Dec'}, 99);

my $start_comundo_aktion1 = timelocal(0, 0, 18, 24, $month_map{'Dec'}, 99);
my $end_comundo_aktion1 =  timelocal(0, 0, 0, 25, $month_map{'Dec'}, 99);

my $time_max = timelocal(0, 0, 0, 1, 0, 135);
my $time_min = 0;

my %tarif_data =
    ( NGI => 
    [ 
      [
       [
	0,			# [ Beginn-, Enddatum ] oder 0
	0,			# | Wochentagsset (0-6) oder 0
	0,			# [ Beginn-, Endzeit ] oder 0
	],
       [
	4.89 / $secs_per_min,	# Betrag in Pfg
	1,			# Taktdauer in Sekunden
	0,			# Zählung ab: (1) Telefonverbindung oder (0) PPP Verbindung
	0,			# Verbindungentgeld (Einwahlstrafe)
	0,			# Tarif-ID (Konvention: 1=Basistarif)  2... Anwendung für Zeittakte (n < 0 überschreibt |n| )
	],
       ]],
    NGI_SH => [[[0, 0, 0], [4.89 / 60, 1, 0, 0, 0],],],
    NIKOMA => 
    [
     [[[$time_min, $start_nikoma2], 0, 0], [4.9 / 60, 1, 1, 0, 1],],
     [[[$start_nikoma2, $time_max], 0, [8 * $secs_per_hour, 24 * $secs_per_hour]], [4.79 / 60, 1, 1, 0, 1],],
     [[[$start_nikoma2, $time_max], 0, [0 * $secs_per_hour, 1 * $secs_per_hour]], [4.79 / 60, 1, 1, 0, 1],],
     [[[$start_nikoma2, $time_max], 0, [1 * $secs_per_hour, 8 * $secs_per_hour]], [2.99 / 60, 1, 1, 0, 1],],
     ],
    KNUUT_0800 => 
    [
     [[[$time_min, $start_knuut_08002], 0, 0], [6.5 / 60, 1, 1, 0, 1],],
     [[[$start_knuut_08002, $time_max], 0, 0], [5 / 60, 1, 1, 0, 1],],
     ],
    KNUUT_MCI =>
    [
     [[[$time_min, $start_knuut_mci2], [0, 1, 2, 3, 4, 5,], [8 * $secs_per_hour, 20 * $secs_per_hour]], [3 / 60, 1, 1, 0, 2],],
     [[[$time_min, $start_knuut_mci2], 0, [9 * $secs_per_hour, 18 * $secs_per_hour]], [8.4 / 60, 1, 1, 0, 1],],
     [[[$time_min, $start_knuut_mci2], 0, [18 * $secs_per_hour, 21 * $secs_per_hour]], [4.8 / 60, 1, 1, 0, 1],],
     [[[$time_min, $start_knuut_mci2], 0, [21 * $secs_per_hour, 24 * $secs_per_hour]], [3 / 60, 1, 1, 0, 1],],
     [[[$time_min, $start_knuut_mci2], 0, [0 * $secs_per_hour, 5 * $secs_per_hour]], [3 / 60, 1, 1, 0, 1],],
     [[[$time_min, $start_knuut_mci2], 0, [5 * $secs_per_hour, 9 * $secs_per_hour]], [4.8 / 60, 1, 1, 0, 1],],

     [[[$start_knuut_mci2, $time_max], [0, 1, 2, 3, 4, 5,], [8 * $secs_per_hour, 20 * $secs_per_hour]], [2 / 60, 1, 1, 0, 2],],
     [[[$start_knuut_mci2, $time_max], 0, [9 * $secs_per_hour, 18 * $secs_per_hour]], [4.6 / 60, 1, 1, 0, 1],],
     [[[$start_knuut_mci2, $time_max], 0, [18 * $secs_per_hour, 21 * $secs_per_hour]], [3.5 / 60, 1, 1, 0, 1],],
     [[[$start_knuut_mci2, $time_max], 0, [21 * $secs_per_hour, 24 * $secs_per_hour]], [2.3 / 60, 1, 1, 0, 1],],
     [[[$start_knuut_mci2, $time_max], 0, [0 * $secs_per_hour, 9 * $secs_per_hour]], [2.3 / 60, 1, 1, 0, 1],],
     ], KNUUT => 
    [
     [[0, [0, 1, 2, 3, 4, 5,], [8 * $secs_per_hour, 20 * $secs_per_hour]], [2 / 60, 1, 1, 0, 2],],

     [[[$time_min, $start_sel530_knuut], 0, [5 * $secs_per_hour, 9 * $secs_per_hour]], [12, 2.5 * $secs_per_min, 1, 0, 1],],
     [[[$time_min, $start_sel530_knuut], 0, [9 * $secs_per_hour, 18 * $secs_per_hour]], [12, 1.5 * $secs_per_min, 1, 0, 1],],
     [[[$time_min, $start_sel530_knuut], 0, [18 * $secs_per_hour, 21 * $secs_per_hour]], [12, 2.5 * $secs_per_min, 1, 0, 1],],
     [[[$time_min, $start_sel530_knuut], 0, [21 * $secs_per_hour, 24 * $secs_per_hour]], [12, 4 * $secs_per_min, 1, 0, 1],],
     [[[$time_min, $start_sel530_knuut], 0, [0 * $secs_per_hour, 5 * $secs_per_hour]], [12, 4 * $secs_per_min, 1, 0, 1],],

     [[[$start_sel530_knuut, $time_max], 0, [5 * $secs_per_hour, 9 * $secs_per_hour]], [8.4, 2.5 * $secs_per_min, 1, 0, 1],],
     [[[$start_sel530_knuut, $time_max], 0, [9 * $secs_per_hour, 18 * $secs_per_hour]], [8.4, 1.5 * $secs_per_min, 1, 0, 1],],
     [[[$start_sel530_knuut, $time_max], 0, [18 * $secs_per_hour, 21 * $secs_per_hour]], [8.4, 2.5 * $secs_per_min, 1, 0, 1],],
     [[[$start_sel530_knuut, $time_max], 0, [21 * $secs_per_hour, 24 * $secs_per_hour]], [8.4, 4 * $secs_per_min, 1, 0, 1],],
     [[[$start_sel530_knuut, $time_max], 0, [0 * $secs_per_hour, 5 * $secs_per_hour]], [8.4, 4 * $secs_per_min, 1, 0, 1],],
     ], DELLNET => 
    [
     [[[$time_min, $time_max], 0, [5 * $secs_per_hour, 9 * $secs_per_hour]], [8.4, 2.5 * $secs_per_min, 1, 0, 1],],
     [[[$time_min, $time_max], 0, [9 * $secs_per_hour, 18 * $secs_per_hour]], [8.4, 1.5 * $secs_per_min, 1, 0, 1],],
     [[[$time_min, $time_max], 0, [18 * $secs_per_hour, 21 * $secs_per_hour]], [8.4, 2.5 * $secs_per_min, 1, 0, 1],],
     [[[$time_min, $time_max], 0, [21 * $secs_per_hour, 24 * $secs_per_hour]], [8.4, 4 * $secs_per_min, 1, 0, 1],],
     [[[$time_min, $time_max], 0, [0 * $secs_per_hour, 5 * $secs_per_hour]], [8.4, 4 * $secs_per_min, 1, 0, 1],],
     ], COMUNDO => 
    [
    [[[$time_min, $time_max], 0, [5 * $secs_per_hour, 9 * $secs_per_hour]], [12, 2.5 * $secs_per_min, 1, 0, 1],],
    [[[$time_min, $time_max], 0, [9 * $secs_per_hour, 18 * $secs_per_hour]], [12, 1.5 * $secs_per_min, 1, 0, 1],],
    [[[$time_min, $time_max], 0, [18 * $secs_per_hour, 21 * $secs_per_hour]], [12, 2.5 * $secs_per_min, 1, 0, 1],],
    [[[$time_min, $time_max], 0, [21 * $secs_per_hour, 24 * $secs_per_hour]], [12, 4 * $secs_per_min, 1, 0, 1],],
    [[[$time_min, $time_max], 0, [0 * $secs_per_hour, 5 * $secs_per_hour]], [12, 4 * $secs_per_min, 1, 0, 1],],
     # zeitbegrenzte Aktionstarife
    [[[$start_comundo_aktion1, $end_comundo_aktion1], 0, [0 * $secs_per_hour, 24 * $secs_per_hour]], [0, 4 * $secs_per_min, 1, 0, 1],],
     ], COMUNDO_030 => 
    [
     [[[$time_min, $time_max], 0, [5 * $secs_per_hour, 9 * $secs_per_hour]], [8.4, 2.5 * $secs_per_min, 1, 0, 1],],
     [[[$time_min, $time_max], 0, [9 * $secs_per_hour, 18 * $secs_per_hour]], [8.4, 1.5 * $secs_per_min, 1, 0, 1],],
     [[[$time_min, $time_max], 0, [18 * $secs_per_hour, 21 * $secs_per_hour]], [8.4, 2.5 * $secs_per_min, 1, 0, 1],],
     [[[$time_min, $time_max], 0, [21 * $secs_per_hour, 24 * $secs_per_hour]], [8.4, 4 * $secs_per_min, 1, 0, 1],],
     [[[$time_min, $time_max], 0, [0 * $secs_per_hour, 5 * $secs_per_hour]], [8.4, 4 * $secs_per_min, 1, 0, 1],],
     ],
    );

my $db_start_time = time ();
sub db_time () {
    time ();
#    (time () - $db_start_time) + timelocal(3, 54, 13, 1, 11, 99);
#    (time () - $db_start_time) + timelocal(3, 45, 19, 1, 11, 99);
#    (time () - $db_start_time) + timelocal(3, 54, 8, 1, 11, 99);
#    (time () - $db_start_time) + timelocal(3, 54, 13, 5, 1, 99);  # Tuesday
#   (time () - $db_start_time) + timelocal(0, 1, 18, 24, $month_map{'Dec'}, 99);
}

sub tarif ( $$ ) {
    my ($isp, $time) = @_;
    my @result=();
    my @switchpoints=();
    my @switchpoints_rel=();
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
#    die unless exists ($tarif_data{$isp});
    my $rec_ref = $tarif_data{$isp};
    record: foreach my $i (@$rec_ref) {
	my $iv = $$i[0];
	if (ref ($$iv[0])) {
	    # date interval
#	    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime ($time) unless defined $sec;
	    my $daiv = $$iv[0];
	    next record unless $$daiv[0] <= $time && $time < $$daiv[1];
	}
	if (ref ($$iv[1])) {
	    # weekday interval
	    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime ($time) unless defined $sec;
	    my $wdiv = $$iv[1];
	    foreach my $wd (@$wdiv) {
		goto found if ($wd == $wday);
	    }
	    next record;
	  found:;
	}
	if (ref ($$iv[2])) {
	    # daytime interval
	    ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime ($time) unless defined $sec;
	    my $dtiv = $$iv[2];
	    my $dt = $sec + $min * $secs_per_min + $hour * $secs_per_hour;
	    next unless ($$dtiv[0] <= $dt && $dt < $$dtiv[1]);
	    $switchpoints[$#switchpoints+1] = $$dtiv[0];
	    $switchpoints[$#switchpoints+1] = $$dtiv[1];
	    {
		my $tmp = $$dtiv[0] - $dt;
		$tmp += $secs_per_day if $tmp <= 0;
		$switchpoints_rel[$#switchpoints_rel+1] = $tmp;
		$tmp = $$dtiv[1] - $dt;
		$tmp += $secs_per_day if $tmp <= 0;
		$switchpoints_rel[$#switchpoints_rel+1] = $tmp;
	    }
	}
	{
	    my $tmp = $$i[1];
	    $result[$$tmp[$offs_rate_id]] = $$i[1];
	}
    }
    my @rates=();
    foreach my $i (@result) {
	$rates[$#rates+1] = $i if defined $i;
    }
    die "missing rate for $isp" if $#result < 0;
    \ (@rates, @switchpoints, @switchpoints_rel);
}

sub calc_price ( $$$ ) {
    my ($isp, $start_time, $duration) = @_;
    my @tmp = tarif ($isp, $start_time);
    my $tar_ref = $tmp[0];
    my $result=0;
    die unless ref ($tar_ref);
    foreach my $tar (@$tar_ref) {
	$result +=  $$tar[0] * $duration / $$tar[1];
    }
    $result;
}

#- end library

# State Transition Commands
my @commands_on_startup = ();
my @commands_before_dialing = (\&clear_gui_counter);
my @commands_on_connect = (\&init, \&main_window_iconify, \&update_gui_online);
my @commands_on_connect_failure = (\&update_gui_offline, \&clear_gui_counter);
my @commands_on_disconnect = (\&main_window_deiconify, \&update_gui_offline, \&update_gui_counter);
# GUI Transition Commands
my @commands_on_gui_deiconify = ();

my ($state_startup, $state_offline, $state_dialing, $state_online) = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9);
my $state=$state_startup;

my %records;
my @template_rate_record = (0, 0);
my ($offs_sum, $offs_time_last) = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9);

my $time_start = 0;

sub init () {
    print STDERR "trace: init()\n";
    $time_start = db_time ();
    foreach my $isp (@isps) {
	$records{$isp}= [];
    }
}

sub cb_disconnect ();
sub main_window_iconify ();
sub main_window_deiconify ();
sub update_gui_offline ();
sub update_gui_counter ();
sub clear_gui_counter ();

sub gui_trans_deiconify () {
    printf STDERR "trace: %s()\n", "gui_trans_deiconify";
    foreach my $cmd (@commands_on_gui_deiconify) {
	&$cmd;
    }
}

sub state_trans_startup_to_offline () {
    printf STDERR "trace: %s()\n", "state_trans_startup_to_offline";
    $state = $state_offline;
    foreach my $cmd (@commands_on_startup) {
	&$cmd;
    }
}

sub state_trans_offline_to_dialing () {
    printf STDERR "trace: %s()\n", "state_trans_offline_to_dialing";
    $state = $state_dialing;
    foreach my $cmd (@commands_before_dialing) {
	&$cmd;
    }
}

sub state_trans_dialing_to_online () {
    printf STDERR "trace: %s()\n", "state_trans_dialing_to_online";
    $state = $state_online;
    foreach my $cmd (@commands_on_connect) {
	&$cmd;
    }
}

sub state_trans_dialing_to_offline () {
    printf STDERR "trace: %s()\n", "state_trans_dialing_to_offline";
    $state = $state_offline;
    foreach my $cmd (@commands_on_connect_failure) {
	&$cmd;
    }
}

sub state_trans_online_to_offline () {
    printf STDERR "trace: %s()\n", "state_trans_online_to_offline";
    $state = $state_offline;
    foreach my $cmd (@commands_on_disconnect) {
	&$cmd;
    }
}

sub socket_exists () {
    (-S '/tmp/.ppp');
}

sub online () {
   $db_ready || (-S '/tmp/.ppp' and qx(/usr/sbin/pppctl 2>/dev/null -p '' -v '/tmp/.ppp' quit) =~ /^PPP/);
}

sub check_online () {
    if (online ()) {
	if ($state == $state_dialing) {
	    state_trans_dialing_to_online ();    
	    2;
	} else {
	    1;
	}
    } else {
	0;
	if ($state == $state_online) {
	    state_trans_online_to_offline ();    
	    -1;
	} elsif (0 and $state == $state_dialing) {
	    state_trans_dialing_to_offline ();    
	    -1;
	}
    }
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

sub update_sum () {
    print STDERR "trace: update_sum()\n";
    my $time_curr = db_time ();
    foreach my $isp (@isps) {
	my @tmp = tarif ($isp, $time_curr);
	my $rates = $tmp[0];
	my $swp = $tmp[2];
	foreach my $rate (@$rates) {
	    my $tmp =  $records{$isp};
	    my $id = $$rate[$offs_rate_id];
	    unless (defined $$tmp[$id]) {
		my @tmp2 = @template_rate_record;
		$$tmp[$id] = \ @tmp2;
	    }
	    my $rec = $records{$isp}[$$rate[$offs_rate_id]];
	    $rec = $$tmp[$id];

	    if ($$rec[$offs_time_last] == 0) {
		$$rec[$offs_sum] = $$rate[$offs_pfg_per_connection];
		$$rec[$offs_time_last] = $time_start - ($$rate[$offs_sw_start_time] * $ppp_offset);
	    }
	    my $units_curr = ($time_curr - $$rec[$offs_time_last]) / $$rate[$offs_secs_per_clock];
	    while ($$rec[$offs_time_last] < $time_curr) {
		die unless $$rate[$offs_secs_per_clock] > 0;
		$$rec[$offs_time_last] +=  $$rate[$offs_secs_per_clock];
		$$rec[$offs_sum] +=  $$rate[$offs_pfg_per_clock];
	    }
	}
    }
}


## Tk-GUI
use Tk;

sub update_gui_offline ();
sub update_gui_online ();
sub update_gui ();
sub cb_disconnect ();
sub cb_dialup2 ( $ );
sub cb_dialup ( $ );
sub make_gui_mainwindow ();

my $main_widget;
my @entries;
my %labels;
my $disconnect_button;

my %widgets;
my $rtc_widget;
my ($offs_record, $offs_isp_widget, $offs_sum_widget, $offs_min_price_widget) = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9);



sub update_gui_dial_state ( $ ) {
    my ($color) = @_;
    foreach my $isp (@isps) {
	my $label =  $labels{$isp};
	my $bg_color = ($isp ne $isp_curr) ? $label->parent->cget('-background') : $color;
	$label->configure(-background => $bg_color);
    }
}

sub update_gui_offline () {
    update_gui_dial_state ('Grey');
}

sub update_gui_online () {
    update_gui_dial_state ('Cyan');
}


sub clear_gui_counter () {
    my $isp;
    foreach my $wid (%widgets) {
	do { $isp = $wid; next; } unless ref $wid;
	print "$isp<---->$isp_curr\n";
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
    my $isp;
    my $cheapest=999999;
    my $most_expensive=0;

    foreach my $isp (@isps) {
	my $i = get_sum ($isp);
	$cheapest = $i if $cheapest > $i;
	$most_expensive = $i if $most_expensive < $i;
    }

    foreach my $wid (%widgets) {
	if (! ref $wid) {
	    $isp = $wid;
	    next;
	}
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
    my $isp;
    foreach my $wid (%widgets) {
	if (! ref $wid) {
	    $isp = $wid;
	    next;
	}
	my $widget=$$wid[$offs_min_price_widget];
	$widget->delete ('1.0', 'end');
	$widget->insert('1.0', sprintf ("%.2f", calc_price ($isp, $curr_time, 60)));
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

sub update_gui () {
    my $ready = check_online ();
    my $curr_time = db_time();

    if ($state == $state_online) {
	my $i=0;
	update_sum ();
    }

    if ($main_widget->state eq 'normal') {
	if (socket_exists ()) {
	    $disconnect_button->configure(-state => 'normal');
	} else {
	    $disconnect_button->configure(-state => 'disabled');
	}
	update_gui_counter () if  ($state == $state_online);
	update_gui_pfg_per_minute ($curr_time);
	update_gui_rtc ();
    }
}


sub cb_disconnect () {
    if ($db_ready or -S '/tmp/.ppp') {
	qx(/usr/sbin/pppctl /tmp/.ppp close);
	# remove highlight on isp labels
	foreach my $isp (@isps) {
	    my $label =  $labels{$isp};
	    my $bg_color = ($isp ne $isp_curr) ? $label->parent->cget('-background') : 'Grey';
	    $label->configure(-background => $bg_color);
 	}
    }
    wait;
    0;
}

my %isp_cmd_map = (KNUUT => 'connect-isp-030.pl', KNUUT_MCI =>  'connect-isp.pl', KNUUT_0800 => 'connect-isp-0800.pl',
		   NIKOMA => 'connect-isp-nikoma.pl', NGI => 'connect-isp-ngi.pl', NGI_SH => 'connect-isp-ngi-sh.pl',
		   COMUNDO => 'connect-isp-comundo.pl', COMUNDO_030 => 'connect-isp-comundo-030.pl',
		   DELLNET => 'connect-isp-dellnet.pl');
my %isp_label_map = (KNUUT => 'Knuut-030', KNUUT_MCI =>  'Knuut-MCI',  KNUUT_0800 => 'Knuut-0800',
		     NIKOMA => 'NIKOMA', NGI => 'NGI', NGI_SH => 'NGI Short',
		     COMUNDO => 'Comundo', COMUNDO_030 => 'Comundo-030', DELLNET => 'Dell Net');
my %isp_color_map = (KNUUT => 'Red', KNUUT_MCI =>  'Blue',  KNUUT_0800 => 'Goldenrod',
		     NIKOMA => 'Purple', NGI => 'DarkGreen', NGI_SH => 'DarkGreen',
		     COMUNDO => 'Salmon', COMUNDO_030 => 'Sienna', DELLNET => 'Sienna');
sub cb_dialup2 ( $ ) {
    my ($isp) = @_;
    my $cmd = "/root/bin/pc/" . $ENV{'USER'} . "/" . $isp_cmd_map{$isp} . '&';
    $isp_curr = $isp;
    state_trans_offline_to_dialing ();
    my $pid = fork();
    if ($pid == 0) {
	unless (exec ($cmd)) {
	    $state=$state_offline;
	    exec ('echo') or die; # FIXME: die will not work properly in a Tk callback
	}
    } elsif (! defined ($pid)) {
	$isp_curr = '';
    } else {
	if (check_online () > 0) {
	    update_gui_online ();
	} else {
	    update_gui_dial_state ('Yellow');
	}
#	$disconnect_button->configure(-state => 'active');
    }
}

sub cb_dialup ( $ ) {
    my ($isp) = @_;
    cb_disconnect ();
    cb_dialup2 ($isp);
}

sub make_diagram ( $$$$ ) {
    my ($win, $canvas, $xmax, $ymax) = @_;
    my ($width, $height) = ($canvas->width - 60, $canvas->height - 60);
    my ($xscale, $yscale) = ($width/$xmax, $height/$ymax); # convinience
    my ($xoffs, $yoffs) = (30, -30);

    $canvas->delete($canvas->find('all'));

    if (0)
    {
	my $field_width = $width / ($#isps+1);
	my $x = $xoffs + $field_width / 2;
	foreach my $isp (@isps) {
	    $canvas->createText($x, 10,
				-width => $field_width,
				-text => $isp_label_map{$isp},
				-fill => $isp_color_map{$isp});
	    $x += $field_width;
	}
    } 
    for (my $i=0; $i <= $xmax; $i+=60) {
	my $x = $i * $xscale + $xoffs;
	$canvas->createLine($x, -$yoffs, $x, -$yoffs + $height,
			    -fill => ($i%300) ? 'Grey80' : 'Grey65');
	if (($i%300) == 0) {
	    $canvas->createText($x, $height - $yoffs + 10,
				-text => sprintf ("%u",  $i / 60));
	}
    }

    for (my $i=0; $i <= $ymax; $i+=10) {
	my $y = -($i * $yscale + $yoffs - $height);
	$canvas->createLine($xoffs, $y, $width + $xoffs,  $y,
			    -fill => ($i%50) ? 'Grey80' : 'Grey65');
	if (($i%50) == 0) {
	    $canvas->createText(10, $y, -text => sprintf ("%0.1f", $i / 100));
	}
    }

    if (1) {
	my $y=40;
	foreach my $isp (@isps) {
	    $canvas->createText(40, $y,
				-text => $isp_label_map{$isp},
				-anchor => 'w',
				-fill => $isp_color_map{$isp});
	    
	    $y+=13;
	}
    }


    foreach my $isp (reverse (@isps)) {
	my $time=db_time();
	my $restart_x=0; 
	my $restart_y=0;
      restart: {
	  my $restart_x1=$restart_x;
	  my $restart_y1=$restart_y;
	  $restart_x = 0; $restart_y = 0;
	  my $flag_do_restart=0;
	  my @graphs=();
	  my @args=();
	  my @tmp = tarif ($isp, $time + $restart_x1);
	  my $tar = $tmp[0];
	  my $swp = $tmp[2];
	  my ($x, $y) = (0, 0);
	  my $is_linear=1;
	  my @data=();
	  my $next_switch=9999999999;
	  foreach my $a (@$tar) {
	      my $offs_time = $$a[$offs_sw_start_time] * $ppp_offset;
	      my $offs_units; { use integer;  $offs_units =  $offs_time / $$a[$offs_secs_per_clock] + 1};
	      my $sum += $offs_units * $$a[$offs_pfg_per_clock] + $$a[$offs_pfg_per_connection];
	      foreach my $i (@$swp) {
		  $next_switch = $i if ($next_switch > $i);
	      }
	      if ($$a[$offs_secs_per_clock] <= 1) {
		  # handle pseudo linear graphs (like 1 second per clock)
		  my $xmax2 =  $xmax;
		  if ($next_switch < $xmax) {
		       $restart_x = $xmax2 = $next_switch;
		      die if $restart_x < $restart_x1;
		      $flag_do_restart=1;
		  }
		  if (! $restart_x1) {
		      $graphs[$#graphs+1]
			  = [ 0, $sum,
			      $xmax2, $sum + $xmax2 *  $$a[$offs_pfg_per_clock] / $$a[$offs_secs_per_clock] ];
		  } else {
		      $graphs[$#graphs+1]
			  = [ $restart_x1, 0,
			      $xmax2, ($xmax2 - $restart_x1) *  $$a[$offs_pfg_per_clock] / $$a[$offs_secs_per_clock] ];
		  }

	      } else {
		  # handle stair graphs (like 150 seconds per clock)
		  my @g = (0, $sum);
		  my $u=$offs_units+1;
		  my $i= $$a[$offs_secs_per_clock] - $offs_time;
		  if ($restart_x1) {
		      @g = ();
		      $i = $restart_x1 + 1;
		      $u = 0;
		  }
		  for (; $i <= $xmax; $i+= $$a[$offs_secs_per_clock]) {
		      if ($i - $restart_x1 > $next_switch) {
			  $restart_x = $next_switch;
			  $flag_do_restart = 1;
			  last;
		      }
		      $g[$#g+1] = $i-1;
		      $g[$#g+1] = $#g > 1 ? $g[$#g-1] : 0;
		      $g[$#g+1] = $i;
		      $g[$#g+1] = $u++ * $$a[$offs_pfg_per_clock];
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
	  $args[$#args+1] = $isp_color_map{$isp};
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
    $win->title('Dialup Manager: Graph');
    my $canvas=$win->Canvas(-width => $width + 40, -height => $height + 40, -background => 'Grey95');
    $canvas->pack(-expand => 1, -fill => 'both');
    $canvas->Tk::bind('<Configure>' => sub { make_diagram ($win, $canvas, $xmax, $ymax) });
}

sub make_gui_mainwindow () {
    $main_widget = MainWindow->new;
    $main_widget->title('Dialup Manager');
    $main_widget->resizable (0, 0);

    my $menubar = $main_widget->Frame (-relief => 'raised');
    my $file_menu_bt = $menubar->Menubutton (-text => 'File');
    my $file_menu = $file_menu_bt->Menu();
    $file_menu_bt->configure (-menu => $file_menu);
    my $edit_menu_bt = $menubar->Menubutton (-text => 'Edit');
    my $edit_menu = $edit_menu_bt->Menu();
    $edit_menu_bt->configure (-menu => $edit_menu);
    my $view_menu_bt = $menubar->Menubutton (-text => 'View');
    my $view_menu = $view_menu_bt->Menu();
    $view_menu_bt->configure (-menu => $view_menu);

#    $file_menu->command (-label => 'Speichern');
    $file_menu->command (-label => 'Trennen', -command => sub { cb_disconnect () });
    $file_menu->command (-label => 'Ende', -command => sub { cb_disconnect () ; exit });

    $edit_menu->command (-label => 'Optionen');

    $view_menu->command (-label => 'Graph 5 min', -command => sub {make_gui_graphwindow(5 * $secs_per_min, 50) });
    $view_menu->command (-label => 'Graph 15 min', -command => sub {make_gui_graphwindow(15 * $secs_per_min, 100) });
    $view_menu->command (-label => 'Graph 30 min', -command => sub {make_gui_graphwindow(30 * $secs_per_min, 200) });
    $view_menu->command (-label => 'Graph 1 h', -command => sub {make_gui_graphwindow(1 * $secs_per_hour, 400) });
#    $view_menu->command (-label => 'Graph 2 h', -command => sub {make_gui_graphwindow(2 * $secs_per_hour, 800) });
    $view_menu->add ('separator');
    $view_menu->add ('checkbutton', -label => 'Uhr',
		     -command => sub {
			 if (!defined $rtc_widget->manager) {
			     $rtc_widget->pack(-side => 'top');
			     } else {
				 $rtc_widget->packForget();
			     }
			 });


    $menubar->pack(-expand => 1, -fill => 'x');
    $file_menu_bt->pack(-side => 'left');
    $edit_menu_bt->pack(-side => 'left');
    $view_menu_bt->pack(-side => 'left');

    my $rtc_frame = $main_widget->Frame;
    $rtc_widget = $rtc_frame->ROText(-height => 1, -width => 34, -takefocus => 0, -insertofftime => 0);

    $rtc_frame->pack(-expand => 1, -fill => 'both' );
    $rtc_widget->pack(-expand => 1, -fill => 'x');

    foreach my $isp (@isps) {
	my $frame = $main_widget->Frame;
	my $button = $frame->Button(-text => 'Verbinden', -command => sub{cb_dialup ($isp)});
#	$button->after(1, sub{cb_dialup2 ($isp)});
	my $label = $frame->Button(-text => (exists $isp_label_map{$isp} ? $isp_label_map{$isp} : $isp),
				   -command => sub{ cb_dialup ($isp) } );
	my $text = $frame->ROText(-height => 1, -width => 12, -takefocus => 0, -insertofftime => 0);
	my $min_price = $frame->ROText(-height => 1, -width => 6, -takefocus => 0, -insertofftime => 0);

	$label->configure(-background => 'Cyan') if ($isp eq $isp_curr);

	$frame->pack(-expand => 1, -fill => 'x');
#	$button->pack(-side => 'left');
	$label->pack(-expand => 1, -fill => 'x', -side => 'left');
	$min_price->pack(-side => 'right');
	$text->pack(-side => 'right');
	$entries[$#entries+1] = $text;
	$labels{$isp} = $label;
	$widgets{$isp} = [0, $label, $text, $min_price];
    }
    {
	my $frame = $main_widget->Frame;
	my $b1 = $frame->Button(-text => 'Trennen', -command => sub{cb_disconnect});
	my $b2 = $frame->Button(-text => 'Graph', -command => sub{make_gui_graphwindow(30 * $secs_per_min, 200)});
	my $b3 = $frame->Button(-text => 'Exp-Graph', -command => sub{exp_make_gui_graphwindow()});
	my $b4; $b4 = $frame->Button(-text => 'test', -command => sub{ $b4->after(1, sub{ sleep 3; print "--\n" }) });
	
#	$b1->pack(-expand => 1, -fill => 'x', -side => 'left');
#	$b2->pack(-expand => 1, -fill => 'x',  -side => 'left');
	$b3->pack(-expand => 1, -fill => 'x',  -side => 'left') if defined &exp_make_gui_graphwindow;
#	$b4->pack(-expand => 1, -fill => 'x',  -side => 'left');
	$frame->pack(-expand => 1, -fill => 'x');
	$disconnect_button=$b1;
    }
    $main_widget->repeat (1000, sub{update_gui()});

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

make_gui_mainwindow();
MainLoop;
