package Dialup_Cost;
## $Id: Dialup_Cost.pm,v 1.3 2000/09/03 21:58:56 bertw Exp bertw $

use strict;
use Time::Local;

BEGIN {
    use Exporter   ();
    use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
    $VERSION = do { my @r = (q$Revision: 1.3 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };
    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    %EXPORT_TAGS = ( );
    @EXPORT_OK   = qw();
}
use vars      @EXPORT_OK;
use vars qw($offs_pfg_per_clock $offs_secs_per_clock $offs_sw_start_time
	    $offs_pfg_per_connection $offs_rate_id $locale_holydays);

# initialize package globals, first exported ones


# then the others (which are still accessible as $Some::Module::stuff)
($offs_pfg_per_clock, $offs_secs_per_clock, $offs_sw_start_time, $offs_pfg_per_connection, $offs_rate_id) = (0,1,2,3,4,5,6,7,8,9);

$locale_holydays=undef; # set by user

# all file-scoped lexicals must be created before
# the functions below that use them.
my $tarif_data_af;
my $tarif_data_ff;

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
my $time_max = timelocal(0, 0, 0, 1, 0, 135);
my $time_min = 0;


# $tarif_data is a reference to a hash
# a value has the following structure:
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
#	1,			# cost unit in seconds (Gebuehreneinheit)
#	0,			# Zählung ab: (1) Telefonverbindung oder (0) PPP Verbindung
#	0,			# money per connection (Verbindungentgeld (Einwahlstrafe))
#	0,			# Tarif-ID (Konvention: 1=Basistarif)  2... Anwendung für Zeittakte (n < 0 überschreibt |n| )
#	],
#       ]],

my $db_start_time = time ();

# make all your functions, whether exported or not;
# remember to put something interesting in the {} stubs

 sub write_list( $ );
 sub write_data( $ );
 sub write_data_ff();
 sub write_data_af();
 sub test_over_midnight( $ );
 sub dup_list( $ );
 sub compile_ff2af ();
 sub read_list( $ );
 sub read_data2( $ );
 sub read_data( $ );
 sub tarif ( $$ );
 sub calc_price ( $$$ );
 sub get_rate( $ );
 sub get_pretty_rate( $ );
 sub get_rate_names();

#-- begin library


sub write_list( $ ) {
    my ($l) = @_;
    my $res = '[';
    foreach my $i (@$l) {
	if (ref ($i)) {
	    $res .= write_list ($i);
	} else {
	    if ($i =~ /\d+/ and $i > 200000) {
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($i);
		$i = sprintf "\'%4u-%02u-%02u %02u:%02u:%02u\'",
		$year+1900, $mon+1, $mday, $hour, $min, $sec;
	    }
	    $res .= "$i, ";
	}
    }
    $res .= '], ';
}
sub write_data( $ ) {
    my ($dat) = @_;
    my $res='';
    while (my ($key, $val) = each (%$dat)) {
      $res .= "$key:\n";
      my $dup = dup_list($val);
      foreach my $ii (@$dup) {
	$res .= write_list ($ii) . "\n";
      }
    }
    $res;
}

sub write_data_ff() {
  write_data ($tarif_data_ff);
}
sub write_data_af() {
  write_data ($tarif_data_af);
}

sub test_over_midnight( $ ) {
  my $r = shift;
  my $time = $$r[$offs_sw_start_time];

  (ref $time and $$time[0] > $$time[1]) ? 1 : 0;
}

# make a deep array copy
sub dup_list( $ ) {
  my $r=shift;
  if (ref $r) {
    my @dup=@$r;
    for my $i (0..$#dup) {
      $dup[$i]=dup_list($dup[$i]);
    }
    \@dup } else { $r }
}

# compile array from config-file format to application format
## read from tarif_data_ff, write to tarif_data_af
sub compile_ff2af () {
  while (my ($rate, $r) = each (%$tarif_data_ff)) {
    my @result;
    for my $i (0..$#$r) {
      my $r0=$$r[$i];
      if (ref $$r0[0]) {
	if (test_over_midnight ($$r0[0])) {
	  # split this rate into before and after midnight parts
	  # this is to make config file easier to generate
	  {
	    my $dup = dup_list ($r0);
	    my $dup0=$$dup[0];
	    my $time=$$dup0[$offs_sw_start_time];
	    $$time[1]=86400;
	    $result[$#result+1]=$dup;
	  }
	  {
	    my $dup = dup_list ($r0);
	    my $dup0=$$dup[0];
	    my $time=$$dup0[$offs_sw_start_time];
	    $$time[0]=0;
	    $result[$#result+1]=$dup;
	  }
	} else {
	  $result[$#result+1]=$r0;
	}
	next;
      }
#      print $rate , "<---\n";
#      print $$r0[0] . "<----\n";  #XXX: stupid?
    }
    $$tarif_data_af{$rate}=\@result;
  }
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
	} elsif ($$in =~ s/^\'(ref:[^\']+)\', //) {
	    $$res[$#$res+1] = $1;              # reference to another rate
	} elsif ($$in =~ s/^(\d+), //) {
	    $$res[$#$res+1] = $1;              # integer
	} elsif ($$in =~ s/^(\d*\.\d+), //) {
	    $$res[$#$res+1] = $1;              # float
	} elsif ($$in =~ s/^\'(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2}):(\d{2})\', //) {
	    $$res[$#$res+1] = timelocal($6, $5, $4, $3, $2 - 1, $1 - 1900) # calendar date
	} elsif ($$in =~ s/^(\w+), //) {
	    $$res[$#$res+1] = $1;              # string
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
	if ($in =~ s/^([A-Z_a-z0-9-]+):\n//) {
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
#    $tarif_data_af = $res;
    $tarif_data_ff=$res;
    compile_ff2af ();
}

sub tarif ( $$ ) {
    my ($isp, $time) = @_;
    my @result=();
    my @switchpoints=();
    my @switchpoints_rel=();
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst);
#    die unless exists ($$tarif_data_af{$isp});
    my $rec_ref = $$tarif_data_af{$isp};
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
	    my $week_day_found=0;
	    foreach my $wd (@$wdiv) {
	      if ($wd =~ /[HW]/) {
		if (test_holyday(sprintf ("%u-%02u-%02u", $year + 1900, $mon+1, $mday))) {
		  goto found if ($wd eq "H");
		  next record if ($wd eq "W");
		}
	      } else {
		# remember a matching weekday but keep looking for holydays/workdays (H/W)
		$week_day_found = 1 if ($wd == $wday);
	      }
	    }
	    next record unless $week_day_found;
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

sub delete_rate( $ ) {
  delete $$tarif_data_af{$_[0]};
  delete $$tarif_data_ff{$_[0]};
}
sub get_rate( $ ) {
    $$tarif_data_af{$_[0]}; # XXX
}
sub get_pretty_rate( $ ) {
    $$tarif_data_ff{$_[0]}; # XXX
}
sub set_pretty_rate( $$ ) {
    $$tarif_data_ff{$_[0]} = $_[1];
    compile_ff2af ();
}
sub get_rate_names() {
    my @result;
    while (my ($name, $rate) = each (%$tarif_data_af)) {
	$result[$#result+1]=$name;
    }
    \@result;
}


# From: sb@en.muc.de (Steffen Beyer)
# Date: 16 Feb 1997 00:57:08 GMT
# Newsgroups: de.sci.mathematik,sdm.general
# Subject: Re: Datum von Ostern 1954 u. 1981?
# Message-ID: <5e5m14$djj$1@en1.engelschall.com>
#
sub oudin_easter( $ ) {
  # Source:

  # http://www.math.uio.no/faq/calendars/faq.html
  # Claus Tondering <ct@login.dknet.dk>
  # http://www.pip.dknet.dk/~pip10160/calendar.html
  # Claus Tondering <c-t@pip.dknet.dk>

  # This algorithm is based on the algorithm of Oudin (1940) and quoted
  # in "Explanatory Supplement to the Astronomical Almanac", P. Kenneth
  # Seidelmann, editor.

  my($year) = @_;
  my($century,$G,$K,$I,$J,$L);
  my($mm,$dd);

  $century = int($year/100);
  $G = $year % 19;
  $K = int(($century - 17)/25);
  $I = ($century - int($century/4) - int(($century - $K)/3) + 19*$G + 15) % 30;
  $I -= int($I/28)*(1 - int($I/28)*int(29/($I + 1))*int((21 - $G)/11));
  $J = ($year + int($year/4) + $I + 2 - $century + int($century/4)) % 7;
  $L = $I - $J;
  $mm = 3 + int(($L + 40)/44);
  $dd = $L + 28 - 31*int($mm/4);
#  sprintf ("%u-%02u-%02u", $year, $mm, $dd);
#  ($mm, $dd);
  timelocal(0, 0, 0, $dd, $mm - 1, $year - 1900);
}

sub holyday_rel_to_abs( $$ ) {
  my ($year, $string)=@_;
  my $result = "";
  if ($string =~ /^(.+)-\(easter([+-]\d+)d?\)$/) {
    my $year_re=$1;
    my $offset=$2 * $secs_per_day;
    my $easter = oudin_easter ($year);
    if ($year =~ /^$year_re$/) {
      my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($easter + $offset);
      $result = sprintf ("%u-%02u-%02u", $year + 1900, $mon+1, $mday);
    }
  } elsif ($string =~ /^(.+)-(\d\d?)-(\d\d?)$/) {
    my $year_re=$1;
    my $month=$2;
    my $mday=$3;
    if ($year =~ /^$year_re$/) {
      $result = sprintf ("%u-%02u-%02u", $year, $month, $mday);
    }
  }
  $result;
}

my $cache_holyday_date="";
my $cache_holyday_result=0;
sub test_holyday( $ ) {
  my ($string)=@_;

  if ($string ne  $cache_holyday_date) {
    return 0 unless defined $locale_holydays;
    $cache_holyday_date=$string;
    $cache_holyday_result=0;
    $string =~ m/^(\d{4})-/ or die "internal error: failed assertion ($string is calendar-date)";
    my $year=$1;
    foreach my $holyday (split (' ', $locale_holydays)) {
      if (holyday_rel_to_abs ($year, $holyday) eq $string) {
	$cache_holyday_result = 1;
	last;
      }
    }
  }
  $cache_holyday_result;
}

1;
END { }       # module clean-up code here (global destructor)
