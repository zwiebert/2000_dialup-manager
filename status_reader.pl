#! /usr/bin/perl -w

$ENV{'PATH'} = '/bin:/usr/bin';
delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV'};

# scan new entries in /var/log/ppp.log
(open PPP_LOG, "tail -n 0 --follow=name /var/log/ppp.log |") or      # GNU
(open PPP_LOG, "tail -n 0 -F /var/log/ppp.log |") or die;                   # BSD

while (<PPP_LOG>) {
    exit if (getppid() == 1);

    if (/: Connection terminated\.$/) {
	syswrite STDOUT, "t", 1;
    } elsif (/: Failed$/) {
	syswrite STDOUT, "f", 1;
    } elsif (/: Exit.$/) {
	syswrite STDOUT, "x", 1;
    } elsif (/: Connect: (ppp\d+) /) {
	syswrite STDOUT, "c", 1;
    }
}
