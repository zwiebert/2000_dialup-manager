package Graphs;
use strict;

BEGIN {
    use Exporter   ();
    use vars       qw($VERSION @ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);
    # set the version for version checking
    $VERSION     = 1.00;
    # if using RCS/CVS, this may be preferred
    $VERSION = do { my @r = (q$Revision: 1.2 $ =~ /\d+/g); sprintf "%d."."%02d" x $#r, @r }; # must be all one line, for MakeMaker

    @ISA         = qw(Exporter);
    @EXPORT      = qw(&add_graphs &steigung &extend_graphs);
    %EXPORT_TAGS = ( );		# eg: TAG => [ qw!name1 name2! ],

    # your exported package globals go here,
    # as well as any optionally exported functions
    @EXPORT_OK   = qw(&add_graphs($$));
}
use vars      @EXPORT_OK;

# non-exported package globals go here
use vars      qw();

# initialize package globals, first exported ones

# then the others (which are still accessible as $Some::Module::stuff)

# all file-scoped lexicals must be created before
# the functions below that use them.

# file-private lexicals go here

# make all your functions, whether exported or not;
# remember to put something interesting in the {} stubs
sub steigung ( $ ) {
    my ($rg) = @_;
    die unless ref ($rg);
    my @g = @$rg;
    my @result=();
    for (my $i=0; $i < $#g-1; $i+=2) {
	my $d1 = ($g[$i+2] - $g[$i+0]);
	my $d = ($d1==0) ? 0 : ($g[$i+3] - $g[$i+1]) / $d1;
	$result[$#result+1]=$d;
    }
    @result;
}

sub dump_list ( $$ ) {
    my ($tag, $list) = @_;
    print "$tag=(";
    foreach my $i (@$list) {  printf "%.2f, ", $i; }
    print ")\n";
}

sub extend_graphs ($$) {
    my ($rg1, $rg2) = @_;
    die unless ref ($rg1) and ref ($rg2);
    if (1) {
	dump_list ("rg1", $rg1);
	dump_list ("rg2", $rg2);
    }
    my @all_x=();
    {
	my $t=0;
	foreach my $x (@$rg1) {
	    next if ($t++%2);
	    $all_x[$#all_x+1]=$x;
	}
    }
    {
	my $t=0;
	foreach my $x (@$rg2) {
	    next if ($t++%2);
	    $all_x[$#all_x+1]=$x;
	}
    }
    @all_x = sort { $Graphs::a <=> $Graphs::b } @all_x;
    {
	my @tmp=();
	foreach my $i (@all_x) {
	    next if ($#tmp >= 0 && $tmp[$#tmp] == $i);
	    $tmp[$#tmp+1] = $i;
	}
	@all_x = @tmp;
    }
    my @ng1 = ();
    my @ng2 = ();

    {
	my @st1 = steigung ($rg1);
	my ($ii, $iii, $iiii) = (0,0,0,0,0,0);
	for (my $i=0; $i <= $#all_x; $i++) {
	    $ng1[$#ng1+1] = $all_x[$i];  # copy x value
	    if ($$rg1[$ii*2] == $all_x[$i]) {
		$ng1[$#ng1+1] = $$rg1[$ii*2+1]; # copy y value (no need for calculate)
		$ii++;
	    } else {
		$ng1[$#ng2+1] =  $ng1[$#ng2-1] + (($all_x[$i] - $all_x[$i-1]) * $st1[$ii-1]); # calculate y value
	    }
	}
    }
    {
	my @st2 = steigung ($rg2);
	my ($ii, $iii, $iiii) = (0,0,0,0,0,0);
	for (my $i=0; $i <= $#all_x; $i++) {
       	    $ng2[$#ng2+1] = $all_x[$i];  # copy x value
	    if ($$rg2[$ii*2] == $all_x[$i]) {
		$ng2[$#ng2+1] = $$rg2[$ii*2+1]; # copy y value (no need for calculate)
		$ii++;
	    } else {
		$ng2[$#ng2+1] =  $ng2[$#ng2-1] + (($all_x[$i] - $all_x[$i-1]) * $st2[$ii-1]); # calculate y value
	    }
	}
    }
    \ (@ng1, @ng2);
}


# add the y values of both graphs GRAPH_REF_1 and GRAPH_REF_2
# Bug: both graphs have to have common values for both first and last x
sub add_graphs( $$ ) {
    my ($rg1, $rg2) = @_;
    die unless ($$rg1[0] == $$rg2[0]);
#    die unless ($$rg1[$#$rg1-1] == $$rg2[$#$rg2-1]);

    my ($rg1e, $rg2e) = extend_graphs ($rg1, $rg2);
    my @result=();
    for (my $i=0; $i <= $#$rg1e; $i+=2) {
	$result[$#result+1]=$$rg1e[$i];
	$result[$#result+1]=$$rg1e[$i+1] + $$rg2e[$i+1];
    }
    @result;
}

1;
END { }       # module clean-up code here (global destructor)
