package Utils;

use strict;
use Time::Local;
BEGIN {
    use Exporter   ();
    use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
    $VERSION = do { my @r = (q$Revision: 1.4 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r };
    @ISA         = qw(Exporter);
    @EXPORT      = qw();
    %EXPORT_TAGS = ();
    @EXPORT_OK   = qw();
}


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


1;
