#! /usr/bin/perl -w
use strict;

$ENV{'PATH'} = '/bin:/usr/bin';
delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV'};
my $db_tracing = defined ($ENV{'DB_TRACING'});

sub db_trace ( $ ) {
   printf STDERR ("trace: %s\n", $_[0]) if $db_tracing;
}

# scan new entries in /var/log/ppp.log
(open PPP_LOG, "tail -n 0 --follow=name /var/log/ppp.log |") or      # GNU
(open PPP_LOG, "tail -n 0 -F /var/log/ppp.log |") or die;            # BSD

syswrite STDOUT, "R", 1;

my $pppd_pid=-1;
my $user_id=$<;
while (<PPP_LOG>) {
    exit if (getppid() == 1);
    if (/pppd\[(\d+)\]: Connection terminated\.$/) {
    	next unless ($pppd_pid == $1);
	syswrite STDOUT, "t", 1;
	exit;
    } elsif (/pppd\[(\d+)\]: Failed$/) {
    	next unless ($pppd_pid == $1);
	syswrite STDOUT, "f", 1;
	exit;
    } elsif (/pppd\[(\d+)\]: Connect script failed$/) {
    	next unless ($pppd_pid == $1);
	syswrite STDOUT, "f", 1;
	exit;
    } elsif (/pppd\[(\d+)\]: Exit.$/) {
    	next unless ($pppd_pid == $1);
	$pppd_pid=-1;
	syswrite STDOUT, "x", 1;
	exit;
db_trace ("$$ $_");
    } elsif (/pppd\[(\d+)\]: Connect: (ppp\d+) /) {
    	next unless ($pppd_pid == $1);
	syswrite STDOUT, "c", 1;
    } elsif (/pppd\[(\d+)\]: pppd .*started by.+ uid (\d+)$/) {
db_trace ("user_id=$user_id / pppd-uid=$2");
    	next unless ($user_id == $2);
	$pppd_pid = $1;
	syswrite STDOUT, "d", 1;
db_trace ("$$ $_");
    }
}

