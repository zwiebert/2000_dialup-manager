#! /usr/local/bin/perl -w

my $isp_curr= defined $ARGV[0] ? $ARGV[0] : '';

use strict;
use Time::Local;
use IO::Handle;
STDOUT->autoflush();

#-- begin library
my %month_map=(Jan => 0, Feb => 1, Mar => 2, Apr => 3, May => 4, Jun => 5,
	       Jul => 6, Aug => 7, Sep => 8, Oct => 9, Nov => 10, Dec => 11);

my $time_start = time ();


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

    if ($isp =~ /^NGI/) {
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
	} else {
	    $takt=2.5 * 60;
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

#- end library

my @sum;
my @time_last = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
my @time_last_isp = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
my @isps = ("KNUUT", "KNUUT_MCI", "KNUUT_0800", "NIKOMA", "NGI"); 

sub update_sum () {
    my $time_curr = time ();
    for (my $i=0; $i <= $#isps; $i++) {
	my @tarif_curr = tarif ($isps[$i], time ());
	if ($time_last[$i] == 0) {
	    $sum[$i] = $tarif_curr[3];
	    $time_last[$i] = $time_start - $tarif_curr[2];
	}
	my $units_curr = ($time_curr - $time_last[$i]) / $tarif_curr[1];
	while ($time_last[$i] < $time_curr) {
	    $time_last[$i] += $tarif_curr[1];
	    $sum[$i] += $tarif_curr[0];
	}
	if ($time_last_isp[$i] == 0) {
	    $time_last_isp[$i] = $time_start;
	}
	$units_curr = ($time_curr - $time_last_isp[$i]) / $tarif_curr[5];
	while ($time_last_isp[$i] < $time_curr) {
	    $time_last_isp[$i] += $tarif_curr[5];
	    $sum[$i] += $tarif_curr[4];
	}
    }
}


while (0) {
    sleep (1);
    update_sum ();
    printf "\r";
    for (my $i=0; $i <= $#isps; $i++) {
	printf " %s: %.3f DM |", $isps[$i], $sum[$i] / 100;
    }
}

## Tk-GUI
use Tk;
my $main;
my @entries;

sub update_gui () {
    my $i=0;
    my $cheapest=999999;
    my $most_expensive=0;
    update_sum ();
    foreach my $i (@sum) {
	$cheapest = $i if $cheapest > $i;
	$most_expensive = $i if $most_expensive < $i;
    }
    foreach my $entry (@entries) {
	my $price = $sum[$i];
	$entry->delete ('1.0', 'end');
	$entry->insert('1.0', sprintf ("%02.3f DM", $price / 100));
	my $bg_color = (($cheapest == $price) ? 'Green'
			: (($most_expensive == $price) ? 'OrangeRed'
			   : 'Yellow'));
	$entry->configure (-background => $bg_color);

	++$i;
    }
}
sub make_gui () {
    $main = MainWindow->new;
    foreach my $isp (@isps) {
	my $frame = $main->Frame;
	my $label = $frame->Label(-text => $isp);
	my $text = $frame->ROText(-height => 1, -width => 10);

	$label->configure(-background => 'Cyan') if ($isp eq $isp_curr);

	$frame->pack(-expand => 1, -fill => 'x');
	$label->pack(-side => 'left');
	$text->pack(-side => 'right');
	$entries[$#entries+1] = $text;
    }
    $main->repeat (1000, sub{update_gui()});
}

make_gui();
MainLoop ;
