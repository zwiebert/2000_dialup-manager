#! /usr/bin/perl

use strict;

my $ndays = ((defined $ENV{'PARAM_NDAYS'}) ? $ENV{'PARAM_NDAYS'} : 7);
my $nmonths = ((defined $ENV{'PARAM_NMONTHS'}) ? $ENV{'PARAM_NMONTHS'} : 6);
my $time=time();

my %data_per_day; 
my @days;
my %data_per_month; 
my @months;

my $days_per_week = 7;
my $hours_per_day = 24;
my $mins_per_hour = 60;
my $mins_per_day = $mins_per_hour * $hours_per_day;
my $secs_per_min = 60;
my $secs_per_hour = $secs_per_min * $mins_per_hour;
my $secs_per_day = $secs_per_hour * $hours_per_day;

sub get_day ($) {
    my ($doffset) = @_;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime ($time + $doffset * $secs_per_day); 
    sprintf ("%u-%02u-%02u",
	     $year+1900, $mon+1, $mday);
}

sub get_month ($) {
    my ($doffset) = @_;
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime ($time); 
}

sub parse_input () {
    while (<>) {
	if (/^\<connect /) {
	    my ($peer, $cost, $start, $duration);
	    $peer= $1 if (m/\bpeer=["'](\w*)['"]/);
	    $cost= $1 if (m/\bcost=["'](\d*\.?\d*)['"]/);
	    $duration= $1 if (m/\bduration=["'](\d*)['"]/);
	    $start=$1 if (m/\bstart=["']([^ ]*)['"]/);
	    next unless defined ($peer) and defined ($cost) and defined ($start) and defined ($duration);
	    my $start_day = substr ($start, 0, 10);
	    my $start_month = substr ($start, 0, 7);

	    # accumulate costs per day
	    if (! defined ($data_per_day{$start_day})) {
		$data_per_day{$start_day} = [$cost, $duration];
		$days[$#days+1]=$start_day;
	    } else {
		my $rec = $data_per_day{$start_day};
		$$rec[0] += $cost;
		$$rec[1] += $duration;
	    }
	    # accumulate costs per month (could be computed from costs-per-day too)
	    if (! defined ($data_per_month{$start_month})) {
		$data_per_month{$start_month} = [$cost, $duration];
		$months[$#months+1]=$start_month;
	    } else {
		my $rec = $data_per_month{$start_month};
		$$rec[0] += $cost;
		$$rec[1] += $duration;
	    }

	}
    }
}

sub print_data_per_day ( $ ) {
    my ($count) = @_;
    foreach my $day (reverse (@days)) {
	last if (--$count < 0);
	my $rec = $data_per_day{$day};
	use integer;
	my $hours = $$rec[1] / $secs_per_hour;
	my $mins = ($$rec[1] / $secs_per_min) % 60;
	no integer;
	printf ("%s: %6.2f DM  %2u:%02u h\n", substr ($day, 5), $$rec[0] / 100, $hours, $mins);
    }
}

sub print_data_per_month ( $ ) {
    my ($count) = @_;
    foreach my $month (reverse (@months)) {
	last if (--$count < 0);
	my $rec = $data_per_month{$month};
	printf "%s: %6.2f DM    %3.0f h\n",  substr ($month, 2), $$rec[0] / 100, $$rec[1] / $secs_per_hour;
    }
}


parse_input ();
if ($ndays > 0) {
    printf "====== Last %2u Days =====\n", $ndays;
    print_data_per_day ($ndays);
}
if ($nmonths > 0) {
    printf "====== Last %2u Months ===\n", $nmonths;
    print_data_per_month ($nmonths);
}
print "=========================\n";
