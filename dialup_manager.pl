#! /usr/local/bin/perl -w

my $db_ready = 0;

my $isp_curr= defined $ARGV[0] ? $ARGV[0] : '';

use strict;
use Time::Local;

#-- begin library
my %month_map=(Jan => 0, Feb => 1, Mar => 2, Apr => 3, May => 4, Jun => 5,
	       Jul => 6, Aug => 7, Sep => 8, Oct => 9, Nov => 10, Dec => 11);


sub parsetime ($) {
    my $time=shift;
    my @result;
    if ($time=~/^([A-Z][a-z][a-z]) ([A-Z][a-z][a-z])  ?([0-3]?[0-9])  ?([0-6]?[0-9]):([0-6]?[0-9]):([0-6]?[0-9]).*(\d{4})/) {
#print     "$1, $2, $3, $4, $5, $6\n";
	@result=($1, $2, $3, $4, $5, $6, $7);
	$result[1]=$month_map{ $result[1] };
    } elsif ($time=~/^(\d{4})-(\d+)-(\d+) (\d+):(\d+):(\d+) ([A-Z]+) ([A-Z][a-z]{2})/) {
	@result=($8, $2, $3, $4, $5, $6, $1, $7);
	$result[1]--;
    } else { die; }
    #WeekDay, Month, Day, hour, minutes, seconds, year, timezone)
    @result;
}
my ($sw_sel530_knuut, $start_sel530_knuut) = (0, timelocal(0, 0, 0, 8, $month_map{'Oct'}, 1999));
my ($sw_knuut_mci2, $start_knuut_mci2) = (0, timelocal(0, 0, 0, 1, $month_map{'Nov'}, 1999));
my ($sw_knuut_08002, $start_knuut_08002) = (0, timelocal(0, 0, 0, 1, $month_map{'Nov'}, 1999));

sub tarif ($$) {
    my ($isp, $date_arg) = @_;
    my $pfg=0;
    my $takt=1;			# 
    my ($isp_pfg, $isp_takt) = (0, 1);
    my $offset=35;		# Dauer der berechneten Login-Phase (normalerweise 30 Sekunden bei V.90)
    my $einwahlstrafe=0;	# Manche Provider berechnen eine Verbindungsgebuehr (T-Online jetzt nicht mehr)
    my @date=parsetime (localtime ($date_arg));

    if ($isp =~ /^NGI/ or $isp =~ /^NGI_SH/) {
	$pfg=4.89 / 60;
	$takt=1;
	$offset=1;
    } elsif ($isp eq "KNUUT_0800") {
	$sw_knuut_08002 = 1 if 
	    ($sw_knuut_08002 == 0 &&
	     ($start_knuut_08002 <= timelocal($date[5], $date[4], $date[3],
					      $date[2], $date[1], $date[6])));
	if (!$sw_knuut_08002) {
	    $pfg=6.0 / 60;
	    $takt=1;
	} else {
	    $pfg=5.0 / 60;
	    $takt=1;
	}
    } elsif ($isp eq "KNUUT_MCI") {
	$sw_knuut_mci2 = 1 if 
	    ($sw_knuut_mci2 == 0 &&
	     ($start_knuut_mci2 <= timelocal($date[5], $date[4], $date[3],
					     $date[2], $date[1], $date[6])));

	if (!$sw_knuut_mci2) {
	    $takt=1;
	    if ($date[3] >= 21 or $date[3] < 5) {
		$pfg=3 / 60;
	    } elsif ($date[0] eq "Sat" or $date[0] eq "Sun") {
		$pfg=4.8 / 60;
	    } else {
		$pfg=4.8 / 60;
	    }
	} else {		# neuer Knuut Tarif
# 09.00-18.00 Uhr 0,046
# 18.00-21.00 Uhr 0,035
# 21.00-09.00 Uhr 0,023
	    $takt=1;
	    if ($date[3] >= 21 or $date[3] < 9) {
		$pfg=2.3 / 60;
	    } elsif ($date[3] >= 18 and $date[3] < 21) {
		$pfg=3.5 / 60;
	    } else {
		$pfg=4.6 / 60;
	    }
	    if (!($date[0] eq "Sat" or $date[0] eq "Sun")
		&& !($date[3] >= 20 or $date[3] < 8)) {
		$isp_pfg = 2.0 / 60;
	    }
		
	}
    } elsif ($isp eq "KNUUT") {
	$sw_sel530_knuut = 1 if 
	    (! $sw_sel530_knuut &&
	     ($start_sel530_knuut <= timelocal($date[5], $date[4], $date[3],
					       $date[2], $date[1], $date[6])));
	$pfg= $sw_sel530_knuut ? 8.4 : 12;

	if ($date[3] >= 21 or $date[3] < 5) {
	    $takt=4 * 60;
	} elsif ($date[0] eq "Sat" or $date[0] eq "Sun") {
	    $takt=2.5 * 60;
	} elsif ($date[3] >= 18 and $date[3] < 21) {
	    $takt=2.5 * 60;
	} else {
	    $takt=1.5 * 60;
	}
	if (!($date[0] eq "Sat" or $date[0] eq "Sun")
	    && !($date[3] >= 20 or $date[3] < 8)) {
	    $isp_pfg = 2.0 / 60;
	}
    } elsif ($isp eq "NIKOMA") {
	$pfg=4.9 / 60;
	$takt=1;
    } elsif ($isp eq "KNUUT_CBC") {
    } else {
    }
#    print "$pfg, $takt, $offset, $einwahlstrafe $isp_pfg $isp_takt\n";
    ($pfg, $takt, $offset, $einwahlstrafe, $isp_pfg, $isp_takt);
}

sub calc_price ( $$$ ) {
    my ($isp, $start_time, $duration) = @_;
    my @tar = tarif ($isp, $start_time);
    my $result = $tar[0] * ($duration / $tar[1]);
    $result +=  $tar[4] * ($duration / $tar[5]);
    $result;
}
#- end library

my $flag_online = 0;
my $flag_dialing = 0;
my $flag_init = 0;
my %records;
my ($offs_sum, $offs_time_last, $offs_time_last_isp) = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9);
#my @sum;
#my @time_last = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
#my @time_last_isp = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
my @isps = ("KNUUT", "KNUUT_MCI", "KNUUT_0800", "NIKOMA", "NGI", "NGI_SH"); 

my $time_start = 0;

sub init () {
    $time_start = time ();
    foreach my $isp (@isps) {
	$records{$isp}=[0, 0, 0];
    }
    $flag_init = 1;
}

sub cb_disconnect ();

sub online () {
    ($flag_online and -S '/tmp/.ppp' and qx(/usr/sbin/pppctl 2>/dev/null -p '' -v '/tmp/.ppp' quit) =~ /^PPP/);
}

sub check_online () {
    if (online ()) {
	if ($flag_init) {
	    1;
	} else {
	    init ();
	    2;
	}
    } elsif ($flag_online) {
	$flag_online=0;
	$flag_init=0;
	-1;
    } else {
	0;
    }
}

sub update_sum () {
    my $time_curr = time ();
    foreach my $isp (@isps) {
	my $rec = $records{$isp};
	my @tarif_curr = tarif ($isp, time ());
	if ($$rec[$offs_time_last] == 0) {
	    $$rec[$offs_sum] = $tarif_curr[3];
	    $$rec[$offs_time_last] = $time_start - $tarif_curr[2];
	}
	my $units_curr = ($time_curr - $$rec[$offs_time_last]) / $tarif_curr[1];
	while ($$rec[$offs_time_last] < $time_curr) {
	    $$rec[$offs_time_last] += $tarif_curr[1];
	    $$rec[$offs_sum] += $tarif_curr[0];
	}
	if ($$rec[$offs_time_last_isp] == 0) {
	    $$rec[$offs_time_last_isp] = $time_start;
	}
	$units_curr = ($time_curr - $$rec[$offs_time_last_isp]) / $tarif_curr[5];
	while ($$rec[$offs_time_last_isp] < $time_curr) {
	    $$rec[$offs_time_last_isp] += $tarif_curr[5];
	    $$rec[$offs_sum] += $tarif_curr[4];
	}
    }
}


## Tk-GUI
use Tk;
my $main;
my @entries;
my %labels;
my $disconnect_button;

my %widgets;
my ($offs_record, $offs_isp_widget, $offs_sum_widget, $offs_min_price_widget) = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9);


sub update_gui_offline () {
    foreach my $isp (@isps) {
	my $label =  $labels{$isp};
	my $bg_color = ($isp ne $isp_curr) ? $label->parent->cget('-background') : 'Grey';
	$label->configure(-background => $bg_color);
    }
}
sub update_gui_online () {
    foreach my $isp (@isps) {
	my $label =  $labels{$isp};
	my $bg_color = ($isp ne $isp_curr) ? $label->parent->cget('-background') : 'Cyan';
	$label->configure(-background => $bg_color);
    }
}


sub update_gui () {
    my $ready = check_online ();
    my $curr_time = time();
    my $cheapest=999999;
    my $most_expensive=0;

    update_gui_offline if ($ready < 0);

    if ($ready > 0) {
	$disconnect_button->configure(-state => 'active') if $disconnect_button->cget('-state') eq 'disabled';
	my $i=0;
	update_sum ();
	foreach my $rec (%records) {
	    next unless ref $rec;
	    my $i = $$rec[$offs_sum];
	    $cheapest = $i if $cheapest > $i;
	    $most_expensive = $i if $most_expensive < $i;
	}
    } else {
	$disconnect_button->configure(-state => 'disabled');
    }

    my $isp;
    foreach my $wid (%widgets) {
	if (! ref $wid) {
	    $isp = $wid;
	    next;
	}
	my $rec=$records{$isp};
	if ($ready > 0) {
	    my $price = $$rec[$offs_sum];
	    my $entry=$$wid[$offs_sum_widget];
	    $entry->delete ('1.0', 'end');
	    $entry->insert('1.0', sprintf ("%4.2f Pfg", $price));
	    my $bg_color = (($cheapest == $price) ? 'Green'
			    : (($most_expensive == $price) ? 'OrangeRed'
			       : 'Yellow'));
	    $entry->configure (-background => $bg_color);
	}

	{			# minute price
	    my $widget=$$wid[$offs_min_price_widget];
	    $widget->delete ('1.0', 'end');
	    $widget->insert('1.0', sprintf ("%.2f", calc_price ($isp, $curr_time, 60)));
	}
    }
}

sub cb_disconnect () {
    if ($db_ready or -S '/tmp/.ppp') {
	qx(/usr/sbin/pppctl /tmp/.ppp close);
	$flag_online=0;
	$flag_init=0;
	# remove highlight on isp labels
	foreach my $isp (@isps) {
	    my $label =  $labels{$isp};
	    my $bg_color = ($isp ne $isp_curr) ? $label->parent->cget('-background') : 'Grey';
	    $label->configure(-background => $bg_color);
 	}
    }
    0;
}

my %isp_cmd_map = (KNUUT => 'connect-isp-030.pl', KNUUT_MCI =>  'connect-isp.pl', KNUUT_0800 => 'connect-isp-0800.pl',
		   NIKOMA => 'connect-isp-nikoma.pl', NGI => 'connect-isp-ngi.pl', NGI_SH => 'connect-isp-ngi-sh.pl');
my %isp_label_map = (KNUUT => 'Knuut-030', KNUUT_MCI =>  'Knuut-MCI',  KNUUT_0800 => 'Knuut-0800',
		     NIKOMA => 'NIKOMA', NGI => 'NGI', NGI_SH => 'NGI Short');
sub cb_dialup2 ( $ ) {
    my ($isp) = @_;
    my $cmd = "/root/bin/pc/" . $ENV{'USER'} . "/" . $isp_cmd_map{$isp} . '&';
    qx/$cmd/;
    $flag_online = 1; # FIXME
    $isp_curr = $isp;
    update_gui_online () if (check_online () > 0);
}

sub cb_dialup ( $ ) {
    my ($isp) = @_;
    cb_disconnect ();
    print $isp . "\n";
    cb_dialup2 ($isp);
}

sub make_gui () {
    $main = MainWindow->new;
    $main->appname('dialupManager');
    foreach my $isp (@isps) {
	my $frame = $main->Frame;
	my $button = $frame->Button(-text => 'Verbinden', -command => sub{cb_dialup ($isp)});
#	$button->after(1, sub{cb_dialup2 ($isp)});
	my $label = $frame->Button(-text => (exists $isp_label_map{$isp} ? $isp_label_map{$isp} : $isp),
				   -command => sub{cb_dialup ($isp)});
	my $text = $frame->ROText(-height => 1, -width => 12);
	my $min_price = $frame->ROText(-height => 1, -width => 6);

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
    my $button = $main->Button(-text => 'Trennen', -command => sub{cb_disconnect});
    $button->pack(-expand => 1, -fill => 'x');
    $disconnect_button=$button;
    $main->repeat (1000, sub{update_gui()});
}

make_gui();
MainLoop ;
