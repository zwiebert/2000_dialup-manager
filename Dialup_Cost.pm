package Dialup_Cost;
## $Id: Dialup_Cost.pm,v 1.2 2000/08/30 22:51:30 bertw Exp bertw $

use strict;
use Time::Local;

BEGIN {
    use Exporter   ();
    use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
    $VERSION = do { my @r = (q$Revision: 1.2 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };
    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    %EXPORT_TAGS = ( );
    @EXPORT_OK   = qw();
}
use vars      @EXPORT_OK;
use vars qw($offs_pfg_per_clock $offs_secs_per_clock $offs_sw_start_time
	    $offs_pfg_per_connection $offs_rate_id);

# initialize package globals, first exported ones


# then the others (which are still accessible as $Some::Module::stuff)
($offs_pfg_per_clock, $offs_secs_per_clock, $offs_sw_start_time, $offs_pfg_per_connection, $offs_rate_id) = (0,1,2,3,4,5,6,7,8,9);

# all file-scoped lexicals must be created before
# the functions below that use them.

# file-private lexicals go here
my $days_per_week = 7;
my $hours_per_day = 24;
my $mins_per_hour = 60;
my $mins_per_day = $mins_per_hour * $hours_per_day;
my $secs_per_min = 60;
my $secs_per_hour = $secs_per_min * $mins_per_hour;
my $secs_per_day = $secs_per_hour * $hours_per_day;

my %month_map=(Jan => 0, Feb => 1, Mar => 2, Apr => 3, May => 4, Jun => 5,
	       Jul => 6, Aug => 7, Sep => 8, Oct => 9, Nov => 10, Dec => 11);
my $start_sel530_knuut = timelocal(0, 0, 0, 8, $month_map{'Oct'}, 99);
my $start_knuut_mci2 = timelocal(0, 0, 0, 1, $month_map{'Nov'}, 99);
my $start_knuut_08002 = timelocal(0, 0, 0, 1, $month_map{'Nov'}, 99);
my $start_nikoma2 = timelocal(0, 0, 0, 1, $month_map{'Dec'}, 99);
my $start_msn = timelocal(0, 0, 0, 21, $month_map{'Feb'}, 99);
my $start_comundo_aktion1 = timelocal(0, 0, 18, 24, $month_map{'Dec'}, 99);
my $end_comundo_aktion1 =  timelocal(0, 0, 0, 25, $month_map{'Dec'}, 99);

my $time_max = timelocal(0, 0, 0, 1, 0, 135);
my $time_min = 0;

my $tarif_data;

# $tarif_data is a reference to a hash
# a value it has the following structure:
#    ( NGI =>                   # hash key (ISP name)
#    [                          # value (reference to array containing all data)
#      [                        # first data entry (later entries overwrite previous)
#       [
#	0,			# [ Beginn-, Enddatum ] oder 0
#	0,			# | Wochentagsset (0-6) oder 0
#	0,			# [ Beginn-, Endzeit ] oder 0
#	],
#       [
#	4.89 / $secs_per_min,	# money per second
#	1,			# Taktdauer in Sekunden
#	0,			# Zählung ab: (1) Telefonverbindung oder (0) PPP Verbindung
#	0,			# money per connection (Verbindungentgeld (Einwahlstrafe))
#	0,			# Tarif-ID (Konvention: 1=Basistarif)  2... Anwendung für Zeittakte (n < 0 überschreibt |n| )
#	],
#       ]],

my $db_start_time = time ();

# make all your functions, whether exported or not;
# remember to put something interesting in the {} stubs

#-- begin library


sub write_list( $ ) {
    my ($l) = @_;
    my $res = '[';
    foreach my $i (@$l) {
	if (ref ($i)) {
	    $res .= write_list ($i);
	} else {
	    if ($i > 200000) {
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($i);
		$i = sprintf "\'%4u-%02u-%02u %02u:%02u:%02u\'",
		$year+1900, $mon+1, $mday, $hour, $min, $sec;
	    }
	    $res .= "$i, ";
	}
    }
    $res .= '], ';
}
sub write_data2( $ ) {
    my ($dat) = @_;
    my $res='';
    foreach my $i (%$dat) {
	if (ref($i)) {
	    foreach my $ii (@$i) {
		$res .= write_list ($ii) . "\n";
	    }
	} else {
	    $res .= "$i:\n";
	}
    }
    $res;
}

sub write_data( $ ) {
    print write_data2 ($tarif_data);
}

sub read_list( $ ) {
    my ($in) = @_;
    my $res = [];
    while ($$in) {
	if ($$in =~ s/^\[//) {
	    $$res[$#$res+1] = read_list ($in); # start a list
	} elsif ($$in =~ s/^\], \n//) {
	    last;                              # end a list
	} elsif ($$in =~ s/^\], //) {
	    last;                              # end a list
	} elsif ($$in =~ s/^(\d+), //) {
	    $$res[$#$res+1] = $1;              # integer
	} elsif ($$in =~ s/^(\d*\.\d+), //) {
	    $$res[$#$res+1] = $1;              # float
	} elsif ($$in =~ s/^\'(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})\', //) {
	    $$res[$#$res+1] = timelocal($6, $5, $4, $3, $2 - 1, $1 - 1900) # calendar date
	} else {
	    last;                              # handle this line in caller because it's not a list
	}
    }
    $res;
}
sub read_data2( $ ) {
    my ($in) = @_;
    my %res;

    while ($in) {
	if ($in =~ s/^([A-Z_0-9-]+):\n//) {
	    $res{$1} = read_list (\$in);
	} else {
	    last;
	}
    }
    \%res;
}
sub read_data( $ ) {
    my ($file) =@_;
    my $data='';
    # slurp in data file
    if (open IN, ($file)) {
	while (<IN>) {
	    $data .= $_;
	}
	close IN;
    } else {
	die "error: cannot open file <$file>\n";
    }
    # parse data
    my $res = read_data2 ($data);
    $tarif_data = $res;
}

sub tarif ( $$ ) {
    my ($isp, $time) = @_;
    my @result=();
    my @switchpoints=();
    my @switchpoints_rel=();
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
#    die unless exists ($$tarif_data{$isp});
    my $rec_ref = $$tarif_data{$isp};
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
    die "missing rate for peer \"$isp\"" if $#result < 0;
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

sub get_rate( $ ) {
    $$tarif_data{$_[0]}; # XXX
}
sub get_rate_names() {
    my @result;
    while (my ($name, $rate) = each (%$tarif_data)) {
	$result[$#result+1]=$name;
    }
    \@result;
}

1;
END { }       # module clean-up code here (global destructor)
