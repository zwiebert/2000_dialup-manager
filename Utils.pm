package Utils;

use strict;
use Time::Local;
BEGIN {
    use Exporter   ();
    use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
    $VERSION = do { my @r = (q$Revision: 1.1 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };
    @ISA         = qw(Exporter);
    @EXPORT      = qw($days_per_week $hours_per_day $mins_per_hour $mins_per_day
		      $secs_per_min $secs_per_hour $secs_per_day);
    %EXPORT_TAGS = ();
    @EXPORT_OK   = qw();
}
use vars @EXPORT_OK;
use vars @EXPORT; # XXX ???
use vars qw($time_correction_offset);

$days_per_week = 7;
$hours_per_day = 24;
$mins_per_hour = 60;
$mins_per_day = $mins_per_hour * $hours_per_day;
$secs_per_min = 60;
$secs_per_hour = $secs_per_min * $mins_per_hour;
$secs_per_day = $secs_per_hour * $hours_per_day;


my $db_tracing = defined ($ENV{'DB_TRACING'});
$time_correction_offset=0; # for Windows95 running on Machine with UTC/GMT clock

# TIME_SUB = localtime or gmtime
sub format_ltime ( $ ) {
  my ($time) = @_;
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime ($time);
  sprintf ("%u-%02u-%02uT%02u:%02u:%02u%s",
	   $year+1900, $mon+1, $mday,
	   $hour, $min, $sec,
	   ($isdst ? "=DST" : ""));
}

sub format_gtime ( $ ) {
  my ($time) = @_;
  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime ($time);
  sprintf ("%u-%02u-%02uT%02u:%02u:%02u%s",
	   $year+1900, $mon+1, $mday,
	   $hour, $min, $sec,
	   ($isdst ? "=DST" : ""));
}

# TIME_SUB = timelocal or timegm
sub parse_time( $$ ) {
    my ($time, $time_sub)= @_;
    my $result=0;
    if ($time=~/^(\d{4})-(\d+)-(\d+)[T ](\d+):(\d+):(\d+)/) {
        # 2000-08-25T18:54:39
        #  1   2  3  4  5  6
	$result = &$time_sub ($6, $5, $4, $3, $2 - 1, $1 - 1900);
      } elsif ($time=~/^\s*(\d{4})-(\d+)-(\d+)\s*$/) {
        # 2000-08-25
        #  1   2  3 
	$result = &$time_sub (0, 0, 0, $3, $2 - 1, $1 - 1900);
      } else { die; }
    $result;
}
sub parse_ltime( $ ) {
  return parse_time ($_[0], \&Time::Local::timelocal);
}
sub parse_gtime( $ ) {
  return parse_time ($_[0], \&Time::Local::timegm);
}


sub db_time () {
  time () + $time_correction_offset * $secs_per_hour;
  #    (time () - $db_start_time) + timelocal(3, 40, 8, 5, 9, 100);
  #    (time () - $db_start_time) + timelocal(3, 54, 13, 1, 11, 99);
  #    (time () - $db_start_time) + timelocal(3, 55, 17, 1, 11, 99);
  #    (time () - $db_start_time) + timelocal(3, 54, 8, 1, 11, 99);
  #    (time () - $db_start_time) + timelocal(3, 54, 13, 5, 1, 99);  # Tuesday
  #    (time () - $db_start_time) + timelocal(0, 1, 18, 24, $month_map{'Dec'}, 99);
}

sub db_trace ( $ ) {
  printf STDERR "trace %s\n", $_[0] if $db_tracing;
}


sub escape_string( $ ) {
    my ($s) = @_;
    $s =~ s/\%/\%25/g;
    $s =~ s/\'/\%27/g;
    $s =~ s/\"/\%22/g;
    $s =~ s/\n/\%0A/g;
#    $s =~ s/\=/\%3d/g;
    $s;
}
sub unescape_string( $ ) {
    my ($s) = @_;
#    $s =~ s/\%3d/\=/g;
    $s =~ s/\%0A/\n/ig;
    $s =~ s/\%27/\'/g;
    $s =~ s/\%22/\"/g;
    $s =~ s/\%25/\%/g;
    $s;
}
#test# print STDERR Utils::unescape_string (Utils::escape_string ("double-quote: \" single-quote: ' percent-sign: %"));



# check LH and RH for common keys.
# Returns three lists: \(@lkeys, @common_keys, @rkeys)
#
sub find_common_keys( $$ ) {
  my ($lh, $rh)=@_;
  my @lres;
  my @cres;
  my @rres;

  foreach my $lk (keys %$lh) {
    if (defined $$rh{$lk}) {
      $cres[++$#cres] = $lk;
    } else {
      $lres[++$#lres] = $lk;
    }
  }

  foreach my $rk (keys %$rh) {
    unless (defined $$lh{$rk}) {
      $rres[++$#rres] = $rk;
    }
  }
  \ (@lres, @cres, @rres);
}
#test#my ($a, $b, $c) = test_2 ({ a=>1, e=>1, c=>1}, { a=>1, f=>1, c=>1}); print "@$a -- @$b -- @$c\n";


sub pretty_filename( $ ) {
  my $file=shift;
  my $home=$ENV{'HOME'} . '/';
  if (substr ($file, 0, length($home)) eq $home) {
    return '~/' . substr ($file, length($home));
  }
  $file;
}


# read/write XML like data
sub read_attributes( $ ) {
  my ($in)=@_;
  my %res;
  while ($$in =~ s/^(\w+)=\"([^\"]+)\"\s*//s
	 or $$in =~ s/^(\w+)=\'([^\']+)\'\s*//s) {
    my ($key, $val) = ($1, $2);
    $res{$key}=Utils::unescape_string($val);
  }
  return \%res;
}

# parse an element into a recursive data structure having this format:
# element =: [ name, \%attrs, \@content ]
# name =: element name (character string)
# attrs =: element attributes (hash reference)
# content =: array of contained element structures or undef  (recursion)
#
sub read_element( $ );
sub read_element( $ ) {
  my $in=shift;
  my $name;
  my $attrs;
  if ($$in =~ s/^\s*\<(\w+)\b\s*//s) {
    $name=$1;
    $attrs = read_attributes($in);
    if ($$in =~ s/^\/\>\s*//s) {
      return [$name, $attrs, undef];
    } elsif ($$in =~ s/^\>\s*//s) {
      my @content;
      until ($$in =~ s/^<\/$name>\s*//s) {
	my $tmp = read_element($in);
	last unless defined $tmp;
	push (@content, $tmp);
      }
      return [$name, $attrs, \@content];
    } else { die "$$in" };
  }
  undef;
}

sub write_element {
  my ($element, $indent)=(@_, '');
  my $res='';
  my ($name, $attrs, $content) = @$element;
  $res .= "$indent<$name ";
  $res .= write_attributes ($attrs);
  if (defined $content) {
    $res =~ s/ $//;
    $res .= ">";
    if (ref $content) {
      $res .= "\n";
      foreach my $element (@$content) {
	$res .= write_element ($element, "$indent  ");
      }
    } else {
      print $content;
    }
    $res .= "$indent</$name>\n";
  } else {
    $res .= "/>\n";
  }
  $res;
}

sub write_attributes( $ ) {
  my ($attr)=@_;
  my $res='';
  while (my ($key, $val) = each (%$attr)) {
    $res .= $key . '="' . Utils::escape_string ($val) . '" ';
  }
  $res;
}

if (0) {
my $input = '<a a1="1" a2="2">
<b a1="1" /></a>';
my $elem = read_element(\$input);
print write_element($elem), "\n";
}

1;
