#! /usr/local/bin/perl -w
## $Id: tkdialup.pl,v 1.7 2000/09/10 06:21:16 bertw Exp bertw $

use strict;
use dm;
use Tk;
use Tk::ROText;
use Tk::ProgressBar;
use Tk::Balloon;

die unless defined $dm::state;

my $APPNAME="tkdialup";
$0 =~ m!^(.*)/([^/]*)$! or die "path of program file required (e.g. ./$0)";
my ($progdir, $progname) = ($1, $2);

## ========================== Preferences  ========================
my %cfg_gui_default= ('.config_tag' => 'gui',
		      balloon_help => '1', show_rtc => '1', show_progress_bar => '1',
		      show_disconnect_button => '1',
		      graph_bgcolor => 'Grey85', graph_nrcolor => 'Grey70', graph_ercolor => 'Grey55',
		      lang => 'de');
my %cfg_gui = %cfg_gui_default;
$cfg_gui{'.config_default'}=\%cfg_gui_default;
my %cfg_tkdialup= ('.config_version' => '1.0', $cfg_gui{'.config_tag'} => \%cfg_gui);
my $cfg_file="${progdir}/dialup_manager.cfg";
my $cfg_file_usr=$ENV{"HOME"} . "/.dialup_manager.cfg";
## ======================= Locale ==================================
my $lang_has_changed=1;  # force reinit
my $current_applang="";
my @wday_names;
my %LOC;
## ========================== Main Window ===========================
my $main_widget;
my %widgets;
my %cmd_button_widgets;
my $disconnect_button;
my $rtc_widget;
my $pb_widget;
my ($offs_record, $offs_isp_widget, $offs_sum_widget, $offs_money_per_minute_widget) = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9);
## ============= Peer Config Editor Window (pcfg) =============================
my @pcfg_widgets;
my @pcfg_labels = ('Name', 'Up Cmd', 'Down Cmd', 'Label', 'Color', 'Rate', 'Visible');
my @pcfg_types =  ('text', 'text',   'text',      'text', 'color', 'text',  'flag');
## ============= Rate Config Editor Window (rcfg) =============================
my @rcfg_widgets;
my $rcfg_current_row=0;
my $rcfg_current_col=0;
## ======================= Misc ========================================
my $db_tracing = defined ($ENV{'DB_TRACING'}); # debug aid
my $app_has_restarted=1; # force reinit
my $color_entry_bg="Grey";      # bg color for Entry widget (depends on OS)
# constants
my $days_per_week = 7;
my $hours_per_day = 24;
my $mins_per_hour = 60;
my $mins_per_day = $mins_per_hour * $hours_per_day;
my $secs_per_min = 60;
my $secs_per_hour = $secs_per_min * $mins_per_hour;
my $secs_per_day = $secs_per_hour * $hours_per_day;


##--- Protos
 sub db_trace( $ );
 sub set_color_entry( $$ );
 sub get_color_entry( $ );
 sub update_gui_dial_state( $ );
 sub update_gui_failure ();
 sub update_gui_offline ();
 sub update_gui_online ();
 sub update_gui_dialing ();
 sub update_progress_bar ();
 sub clear_gui_counter ();
 sub update_gui_counter ();
 sub update_gui_money_per_minute( $ );
 sub update_gui_rtc ();
 sub rtc_max_width ();
 sub update_gui ();
 sub make_diagram( $$$$ );
 sub make_gui_graphwindow( $$ );
 sub make_gui_aboutwindow ();
 sub make_gui_statwindow ();
 sub make_gui_textwindow( $$ );
 sub make_gui_mainwindow ();
 sub main_window_iconify ();
 sub main_window_deiconify ();
 sub mask_widget( $$$$$$ );
 sub pcfg_apply( $$$$ );
 sub rcfg_make_window( $$$$$ );
 sub rcfg_update_matrix( $$ );
 sub rcfg_make_matrix( $ );
 sub rcfg_parse_matrix( $ );
 sub pcfg_start_rcfg( $$ );
 sub pcfg_update_gadgets( $$ );
 sub pcfg_editor_window( $$ );
 sub color_cfg_editor_window( $$ );
 sub read_config( $$$ );
 sub write_config( $ );
 sub save_config();
 sub read_locale( $ );
##---


sub db_trace ( $ ) { printf STDERR "trace %s\n", $_[0] if $db_tracing }

sub set_color_entry( $$ ) {
    my ($entry, $color) = @_;
    $entry->configure(-foreground => $color, -background => $cfg_gui{'graph_bgcolor'})
	if $entry and $color;
}
sub get_color_entry( $ ) {
    my ($entry) = @_;
    $entry->cget('-foreground');
}

sub update_gui_dial_state( $ ) {
    my ($color) = @_;
    foreach my $isp (@dm::isps) {
	next unless (dm::get_isp_flag_active ($isp));
	my $label =  $cmd_button_widgets{$isp};
	if (defined $label) {
	    my $bg_color = ($isp ne $dm::isp_curr) ? $label->parent->cget('-background') : $color;
	    $label->configure(-background => $bg_color);
	}
    }
}

sub update_gui_failure () {
    update_gui_dial_state ('Red');
}

sub update_gui_offline () {
    update_gui_dial_state ('#708dad');
}

sub update_gui_online () {
    update_gui_dial_state ('Cyan');
}

sub update_gui_dialing () {
    update_gui_dial_state ('Yellow');
}


sub update_progress_bar () {
    use integer;
    my $tem = (dm::db_time () - ($dm::time_start - $dm::ppp_offset)) % $dm::curr_secs_per_unit;
    my $percent_done =  ($tem * 100) / $dm::curr_secs_per_unit;
    $pb_widget->value($percent_done);

    no integer;
}


sub clear_gui_counter () {
    while (my ($isp, $wid) = each (%widgets)) {
	my $entry=$$wid[$offs_sum_widget];
	$entry->delete ('1.0', 'end');
	$entry->configure (-background => $color_entry_bg);

# FIXME: move the following
	if ($dm::state == $dm::state_dialing and $isp eq $dm::isp_curr) {
#	    $entry->insert('1.0', 'dialing');
	    $entry->configure (-background => 'Yellow');
	}
    }
}

sub update_gui_counter () {
    my @sums;
    my %sum_cache;

    while (my ($isp, $wid) = each (%widgets)) {
	my $sum = dm::get_sum ($isp);
	$sums[$#sums+1] = $sum;
	$sum_cache{$isp} = $sum;
    }

    @sums = sort {$a <=> $b} @sums;
    my $cheapest = $sums[$[];
    my $most_expensive = $sums[$#sums];

    while (my ($isp, $wid) = each (%widgets)) {
	my $price = $sum_cache{$isp};
	my $widget=$$wid[$offs_sum_widget];
	$widget->delete ('1.0', 'end');
	$widget->insert('1.0', sprintf ("%4.2f Pfg", $price));
	my $bg_color = (($cheapest == $price) ? 'Green'
			: (($most_expensive == $price) ? 'OrangeRed'
#			   : 'Yellow'));
			   : $color_entry_bg));
	$widget->configure (-background => $bg_color);
    }
}

sub update_gui_money_per_minute ( $ ) {
    my ($curr_time)=@_;
    my @tem;
    while (my ($isp, $wid) = each (%widgets)) {
      $tem[$#tem+1]=Dialup_Cost::calc_price (dm::get_isp_tarif($isp), $curr_time, 60);
    }
    @tem = sort {$a <=> $b} @tem;
    my $cheapest = $tem[$[];
    my $most_expensive = $tem[$#tem];

    while (my ($isp, $wid) = each (%widgets)) {
	my $widget=$$wid[$offs_money_per_minute_widget];
	my $price=Dialup_Cost::calc_price (dm::get_isp_tarif($isp), $curr_time, 60);
	$widget->delete ('1.0', 'end');

	$widget->insert('1.0', sprintf ("%.2f", $price));
	my $bg_color = (($cheapest == $price) ? 'LightGreen'
			: (($most_expensive == $price) ? 'Salmon'
#			   : 'LightYellow'));
			   : $color_entry_bg));
	$widget->configure (-background => $bg_color);
    }
}

sub update_gui_rtc () {
    $rtc_widget->delete ('1.0', 'end');
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime (dm::db_time ());
    $rtc_widget->insert('1.0', sprintf (" %s  %u-%02u-%02u  %02u:%02u:%02u",
					$wday_names[$wday],
					$year + 1900, $mon + 1, $mday,
					$hour, $min, $sec,
					));
}
sub rtc_max_width () {
    my $max_wday_len=0;
    my $rtc_time_len=24;
    foreach my $wday (@wday_names) {
	if ((my $len = length ($wday)) > $max_wday_len) { $max_wday_len = $len; }
    }
    $max_wday_len + $rtc_time_len;
}

sub update_gui () {
    my $curr_time = dm::db_time();
    my $state = $dm::state;

    if ($main_widget->state eq 'normal') {
	if ($state == $dm::state_online or $state == $dm::state_dialing) {
	    $disconnect_button->configure(-state => 'normal');
	} else {
	    $disconnect_button->configure(-state => 'disabled');
	}
	update_gui_counter () if ($state == $dm::state_online);
	update_gui_money_per_minute ($curr_time);
	update_gui_rtc ();
	update_progress_bar () if ($state == $dm::state_online);
    }

}

## display time/money graphs
sub make_diagram( $$$$ ) {
    my ($win, $canvas, $xmax, $ymax) = @_;
    my ($width, $height) = ($canvas->width - 60, $canvas->height - 60);
    my ($xscale, $yscale) = ($width/$xmax, $height/$ymax); # convinience
    my ($xoffs, $yoffs) = (30, -30);

    $canvas->delete($canvas->find('all'));

    # print vertical diagram lines and numbers
    for (my $i=0; $i <= $xmax; $i+=60) {
	my $x = $i * $xscale + $xoffs;
	$canvas->createLine($x, -$yoffs, $x, -$yoffs + $height,
			    -fill => ($i%300) ? $cfg_gui{'graph_nrcolor'} : $cfg_gui{'graph_ercolor'});
	if (($i%300) == 0) {
	    $canvas->createText($x, $height - $yoffs + 10,
				-text => sprintf ("%u",  $i / 60));
	}
    }

    # print horizontal diagram lines and numbers
    for (my $i=0; $i <= $ymax; $i+=10) {
	my $y = -($i * $yscale + $yoffs - $height);
	$canvas->createLine($xoffs, $y, $width + $xoffs,  $y,
			    -fill => ($i%50) ? $cfg_gui{'graph_nrcolor'} : $cfg_gui{'graph_ercolor'});
	if (($i%50) == 0) {
	    $canvas->createText(10, $y, -text => sprintf ("%0.1f", $i / 100));
	}
    }

    # print labels in matching color
    if (1) {
	my $y=40;
	foreach my $isp (@dm::isps) {
	    next unless (dm::get_isp_flag_active ($isp));

	    $canvas->createText(40, $y,
				-text => dm::get_isp_label($isp),
				-anchor => 'w',
				-fill => dm::get_isp_color($isp));
	    $y+=13;
	}
    }

    # print graphs in matching color
    foreach my $isp (reverse (@dm::isps)) {
	next unless (dm::get_isp_flag_active ($isp));
	my $time=dm::db_time();
	my $restart_x=0; 
	my $restart_y=0;
	my $part_of_previous_rate=0;
      restart: {
	  my $restart_x1=$restart_x;
	  my $restart_y1=$restart_y;
	  $restart_x = 0; $restart_y = 0;
	  my $flag_do_restart=0;
	  my @graphs=();
	  my @args=();
	  my @tmp =Dialup_Cost::tarif (dm::get_isp_tarif($isp), $time + $restart_x1);
	  my $tar = $tmp[0];   # rate list
	  my $swp = $tmp[2];   # absolute switchpoints (time of changing rates)
	  my ($x, $y) = (0, 0);
	  my $is_linear=1;
	  my @data=();
	  my $next_switch=9999999999;
	  foreach my $a (@$tar) {
	      my $offs_time = $$a[$Dialup_Cost::offs_sw_start_time] * dm::get_ppp_offset_avg($isp);
	      my $offs_units; { use integer;  $offs_units =  $offs_time / $$a[$Dialup_Cost::offs_secs_per_clock] + 1};
	      my $sum += $offs_units * $$a[$Dialup_Cost::offs_pfg_per_clock] + $$a[$Dialup_Cost::offs_pfg_per_connection];
	      foreach my $i (@$swp) {
		  $next_switch = $i if ($next_switch > $i);
	      }
	      if ($$a[$Dialup_Cost::offs_secs_per_clock] <= 1) {
		  # handle pseudo linear graphs (like 1 second per clock) ###############################
		  my $xmax2 =  $xmax;
		  if ($next_switch < $xmax) {
		       $restart_x = $xmax2 = $next_switch;
		      die if $restart_x < $restart_x1;
		      $flag_do_restart=1;
		  }
		  if (! $restart_x1) {
		      $graphs[$#graphs+1]
			  = [ 0, $sum,
			      $xmax2, $sum + $xmax2 *  $$a[$Dialup_Cost::offs_pfg_per_clock] / $$a[$Dialup_Cost::offs_secs_per_clock] ];
		  } else {
		      $graphs[$#graphs+1]
			  = [ $restart_x1, 0,
			      $xmax2, ($xmax2 - $restart_x1) *  $$a[$Dialup_Cost::offs_pfg_per_clock] / $$a[$Dialup_Cost::offs_secs_per_clock] ];
		  }

	      } else {
		  # handle stair graphs (like 150 seconds per clock) ######################################
		  my @g = ($restart_x1) ? ()              : (0, $sum);
		  my $u = ($restart_x1) ? 0               : $offs_units+1;
		  my $i = ($restart_x1) ? $restart_x1 + 1 : $$a[$Dialup_Cost::offs_secs_per_clock]  - $offs_time;

		  while (($i <= $xmax) or ($i - $restart_x1 > $next_switch)) { # FIXME
		      if ($i - $restart_x1 > $next_switch) { # switchpoint reached
			  $restart_x = $next_switch;
			  $flag_do_restart = 1;
			  $part_of_previous_rate 
			      = (($next_switch - ($i - $restart_x1 -  $$a[$Dialup_Cost::offs_secs_per_clock]))
				 ) / $$a[$Dialup_Cost::offs_secs_per_clock];
			  last;
		      }
		      $g[$#g+1] = $i-1;
		      $g[$#g+1] = $#g > 1 ? $g[$#g-1] : 0;
		      $g[$#g+1] = $i;
		      $g[$#g+1] = $u++ * $$a[$Dialup_Cost::offs_pfg_per_clock];

		      $i+= $$a[$Dialup_Cost::offs_secs_per_clock] * (1 - $part_of_previous_rate);
		      $part_of_previous_rate = 0;
		  }
		  if (! $flag_do_restart) {
		      if ($i != $xmax) {
			  $g[$#g+1] = $xmax;
			  $g[$#g+1] = $g[$#g-1];
		      }
		  } else {
		      # we need common last x  for add_graph()
		      $g[$#g+1] = $next_switch;
		      $g[$#g+1] = $g[$#g-1];
		  }
		  $graphs[$#graphs+1] = \ @g;
	      }
	  }
	  my $gref =  $graphs[0];
	  my @graph = @$gref;
	  if ($#graphs > 0) {
	      for (my $i=1; $i <= $#graphs; $i++) {
		  @graph = add_graphs ($gref, $graphs[$i]);
	      }
	  }
	  for (my $i=1; $i <= $#graph; $i+=2) {
	      $graph[$i] += $restart_y1;
	  }
	  {
	      my $t=0;
	      foreach my $i (@graph) {
		  if (++$t%2) {
		      $args[$#args+1] = $i * $xscale + $xoffs;
		  } else {
		      # y
		      $args[$#args+1] = -($i * $yscale - $height + $yoffs);
		  }
	      }
	  }

	  $args[$#args+1] = '-fill';
	  $args[$#args+1] = dm::get_isp_color($isp);
	  $canvas->createLine (@args);

	  if ($flag_do_restart) {
	      $restart_y = $graph[$#graph];
	      goto restart if $flag_do_restart;
	  }
      }
    }
}

sub make_gui_graphwindow( $$ ) {
    my ($xmax, $ymax) = @_; #(30 * $secs_per_min, 200);
    my ($width, $height) = (500, 350);
    my ($xscale, $yscale) = ($width/$xmax, $height/$ymax); # convinience
    my ($xoffs, $yoffs) = (20, -20);
    my $win=$main_widget->Toplevel;
    $win->title("$APPNAME: Graph");
    my $canvas=$win->Canvas(-width => $width + 40, -height => $height + 40, -background => $cfg_gui{'graph_bgcolor'});
    $canvas->pack(-expand => 1, -fill => 'both');
    $canvas->Tk::bind('<Configure>' => sub { make_diagram ($win, $canvas, $xmax, $ymax) });
}

## display about window
sub make_gui_aboutwindow () {
    my $win=$main_widget->Toplevel;
    my ($width, $height) = (200, 200);

    my ($about_txt, $about_lines, $about_columns) = ("", 0, 0);
    if (open (ABT, "$progdir/about-$cfg_gui{'lang'}")) {
	while (<ABT>) {
	    $about_txt .= $_;
	    $about_lines++;
	    my $len = length($_);
	    $about_columns = $len if ($len > $about_columns);
	}
	close (ABT);
    }
    chomp $about_txt;

    $win->title("$APPNAME: About");
    my $txt = $win->ROText(-height => $about_lines,
			   -width => $about_columns,
			   -wrap => 'none'
			   );
    $txt->pack();
    $txt->insert('end', $about_txt);

}

## display money and time statisctics from user owned logfile
sub make_gui_statwindow () {
    make_gui_textwindow ("perl $progdir/stat_new.pl $dm::cost_out_file |",  "$APPNAME: Stat");
}

## display FILE in window with title TITLE
sub make_gui_textwindow ( $$ ) {
    my ($file, $title) = @_;
    my $win=$main_widget->Toplevel;
    my ($width, $height) = (200, 200);

    my ($stat_txt, $stat_lines, $stat_columns) = ("", 0, 0);
    if (open (IN, $file)) {
	while (<IN>) {
	    $stat_txt .= $_;
	    $stat_lines++;
	    my $len = length($_);
	    $stat_columns = $len if ($len > $stat_columns);
	}
	close (IN);
    }
    chomp $stat_txt;

    $win->title("$title");
    my $txt = $win->ROText(-height => $stat_lines,
			   -width => $stat_columns,
			   -wrap => 'none'
			   );
    $txt->pack();
    $txt->insert('end', $stat_txt);
}

sub make_gui_mainwindow () {
    undef %cmd_button_widgets; undef %widgets; # allow restart

    $main_widget = MainWindow->new;
    my $top = $main_widget;
    $top->title("$APPNAME");
    $top->resizable (0, 0);
    my $balloon = $main_widget->Balloon();
    #### Menu ####
    my $menubar = $top->Frame (-relief => 'raised');
    my $file_menu_bt = $menubar->Menubutton (-text => $LOC{'menu_file'});
    my $file_menu = $file_menu_bt->Menu();
    $file_menu_bt->configure (-menu => $file_menu);
    my $edit_menu_bt = $menubar->Menubutton (-text => $LOC{'menu_edit'});
    my $edit_menu = $edit_menu_bt->Menu();
    $edit_menu_bt->configure (-menu => $edit_menu);
    my $view_menu_bt = $menubar->Menubutton (-text => $LOC{'menu_view'});
    my $view_menu = $view_menu_bt->Menu();
    $view_menu_bt->configure (-menu => $view_menu);
    my $help_menu_bt = $menubar->Menubutton (-text => $LOC{'menu_help'});
    my $help_menu = $help_menu_bt->Menu();
    $help_menu_bt->configure (-menu => $help_menu);

#    $file_menu->command (-label => 'Speichern');
    $file_menu->command (-label => $LOC{'menu_file_hangup_now'}, -command => sub { dm::disconnect () });
    $file_menu->add ('checkbutton',
		     -label =>  $LOC{'menu_file_hangup_defer'},
		     -variable => \$dm::flag_stop_defer);
		    

    $file_menu->command (-label => $LOC{'menu_file_save'}, -command => sub { save_config() });
    $file_menu->command (-label => $LOC{'menu_file_quit'}, -command => sub { dm::disconnect () ; exit });

    $edit_menu->command (-label => $LOC{'menu_edit_peer_options'}, -command => sub { pcfg_editor_window (100,200) });
    $edit_menu->command (-label => $LOC{'menu_edit_graph_options'}, -command => sub { color_cfg_editor_window (100,200) });
    $edit_menu->command (-label => $LOC{'menu_edit_rate_options'}, -command => sub { rcfg_editor_window (100,200) });


##--- View Menu
    $view_menu->command (-label => "$LOC{'menu_view_graph'} 5 min ...", -command => sub {make_gui_graphwindow(5 * $secs_per_min, 50) });
    $view_menu->command (-label => "$LOC{'menu_view_graph'} 15 min ...", -command => sub {make_gui_graphwindow(15 * $secs_per_min, 100) });
    $view_menu->command (-label => "$LOC{'menu_view_graph'} 30 min ...", -command => sub {make_gui_graphwindow(30 * $secs_per_min, 200) });
    $view_menu->command (-label => "$LOC{'menu_view_graph'} 1 h ...", -command => sub {make_gui_graphwindow(1 * $secs_per_hour, 400) });
#    $view_menu->command (-label => "$LOC{'menu_view_graph'} 2 h ...", -command => sub {make_gui_graphwindow(2 * $secs_per_hour, 800) });
    $view_menu->add ('separator');
    $view_menu->command (-label => $LOC{'menu_view_stat'}, -command => sub {make_gui_statwindow() });
    $view_menu->add ('separator');
    $view_menu->add ('checkbutton', -label => $LOC{'menu_view_clock'},
		     -variable => \$cfg_gui{'show_rtc'},
		     -command => sub { if (!defined $rtc_widget->manager) { $rtc_widget->pack(-side => 'top'); }
				       else { $rtc_widget->packForget(); } });

    $view_menu->add ('checkbutton', -label => $LOC{'menu_view_progress_bar'},
		     -variable => \$cfg_gui{'show_progress_bar'},
		     -command => sub { if (!defined $pb_widget->manager) {
			                  $pb_widget->pack(-expand => 1, -fill => 'x');
				       } else { $pb_widget->packForget(); } });

    $view_menu->add ('checkbutton', -label => $LOC{'menu_view_disconnect_button'},
		     -variable => \$cfg_gui{'show_disconnect_button'},
		     -command => sub { if (!defined $disconnect_button->manager) {
			                  $disconnect_button->pack(-expand => 1, -fill => 'x');
				       } else { $disconnect_button->packForget(); } });
##---- Help Menu
    $help_menu->add ('checkbutton', -label => $LOC{'menu_help_balloon_help'},
		     -variable => \$cfg_gui{'balloon_help'},
		     -command => sub {
			 $balloon->configure(-state => ($cfg_gui{'balloon_help'} ? 'balloon' : 'none')); });
    $balloon->configure(-state => ($cfg_gui{'balloon_help'} ? 'balloon' : 'none'));

    $help_menu->add ('separator');
    $help_menu->command (-label => $LOC{'menu_help_about'}, -command => sub {make_gui_aboutwindow() });
    $help_menu->command (-label => "Copyright ...", -command => sub {make_gui_textwindow("$progdir/COPYRIGHT", "$APPNAME: Copyright") });

    $balloon->attach($file_menu,
		     -msg => ['',
			      $LOC{'menu_file_hangup_now.help'},
			      $LOC{'menu_file_hangup_defer.help'},
			      $LOC{'menu_file_save.help'},
			      $LOC{'menu_file_quit.help'},
			      ],
                     );
    $balloon->attach($edit_menu,
		     -msg => ['',
			      $LOC{'menu_edit_peer_options.help'},
			      $LOC{'menu_edit_graph_options.help'},
			      $LOC{'menu_edit_rate_options.help'},
			      $LOC{'menu_edit_options.help'},
			      ],
                     );
    $balloon->attach($view_menu,
		     -msg => ['',
			      $LOC{'menu_view_graph.help'},
			      $LOC{'menu_view_graph.help'},
			      $LOC{'menu_view_graph.help'},
			      $LOC{'menu_view_graph.help'},
			      '',
			      $LOC{'menu_view_stat.help'},
			      '',
			      $LOC{'menu_view_clock.help'},
			      $LOC{'menu_view_progress_bar.help'},
			      $LOC{'menu_view_disconnect_button.help'},
			      ,
			      ],);

    $balloon->attach($help_menu,
		     -msg => ['',
			      $LOC{'menu_help_balloon_help.help'},
			      '',
			      $LOC{'menu_help_about.help'},
			      ],
                     );

    $menubar->pack(-expand => 1, -fill => 'x');
    $file_menu_bt->pack(-side => 'left');
    $edit_menu_bt->pack(-side => 'left');
    $view_menu_bt->pack(-side => 'left');
    $help_menu_bt->pack(-side => 'right');

    #### RTC ####
    my $rtc_frame = $top->Frame;
    $rtc_widget = $rtc_frame->ROText(-height => 1, -width => rtc_max_width (), -takefocus => 0, -insertofftime => 0);

    $rtc_frame->pack(-expand => 1, -fill => 'both' );
    $rtc_widget->pack(-expand => 1, -fill => 'x') if $cfg_gui{'show_rtc'};
    $color_entry_bg = $rtc_widget->cget('-bg');

    #### Controls ####
	my $button_frame = $top->Frame;
    {
	my $row=0;
	my $usepack=0;

	unless ($usepack) {
	    my $label;
	    $label=$button_frame->Label(-text => $LOC{'win_main_start'})->grid(-row => $row, -column => 0);
	    $balloon->attach($label, -balloonmsg => $LOC{'win_main_start.help'}) if $balloon;
	    $label=$button_frame->Label(-text => $LOC{'win_main_money'})->grid(-row => $row, -column => 1);
	    $balloon->attach($label, -balloonmsg => $LOC{'win_main_money.help'}) if $balloon;
	    $label=$button_frame->Label(-text => $LOC{'win_main_rate'})->grid(-row => $row, -column => 2);
	    $balloon->attach($label, -balloonmsg => $LOC{'win_main_rate.help'}) if $balloon;
	    $row++;
	}

	foreach my $isp (@dm::isps) {
	    next unless (dm::get_isp_flag_active ($isp));
	    my $frame = $usepack ? $button_frame->Frame : $button_frame;
		
	    my $cmd_button = $frame->Button(-text => dm::get_isp_label ($isp),
				       -command => sub{ dm::dialup ($isp) } );
	    my $money_counter = $frame->ROText(-height => 1, -width => 10, -takefocus => 0, -insertofftime => 0);
	    my $money_per_minute = $frame->ROText(-height => 1, -width => 5, -takefocus => 0, -insertofftime => 0);
	    $cmd_button->configure(-background => 'Cyan') if ($isp eq $dm::isp_curr);

	    if ($usepack) {
		$cmd_button->pack(-expand => 1, -fill => 'x', -side => 'left');
		$money_per_minute->pack(-side => 'right');
		$money_counter->pack(-side => 'right');
		$frame->pack(-expand => 1, -fill => 'x');
	    } else {
		$cmd_button->grid(-column => 0, -row => $row, -sticky => "ew");
		$money_counter->grid(-column => 1, -row => $row, -sticky => "ew");
		$money_per_minute->grid(-column => 2, -row => $row, -sticky => "ew");
	    }
	    $cmd_button_widgets{$isp} = $cmd_button;
	    $widgets{$isp} = [0, $cmd_button, $money_counter, $money_per_minute];
	    $row++;
	}
	    $button_frame->pack(-expand => 1, -fill => 'x');
    }
    my @tmp = $button_frame->gridBbox;
    db_trace ("@tmp");

    #### Progress Bar ####
    {
	my $pb_frame=$top->Frame();
	my $pb = $pb_frame->ProgressBar
	    (
#	     -length => 220,
	     -width => 8,
	     -from => 100,
	     -to => 0,
	     -blocks => 10,
	     -colors => [0, 'green', 50, 'yellow' , 80, 'red'],
#	     -variable => \$percent_done,
#	     -relief => 'sunken',
	     -pady => 1,
	     -padx => 1,
	     );
	$pb->pack(-expand => 1, -fill => 'x') if $cfg_gui{'show_progress_bar'};
	$pb_widget = $pb;
	$pb_frame->pack(-expand => 1, -fill => 'x');
    }
    {
	my $frame = $top->Frame;
	$disconnect_button = $frame->Button(-text => "$LOC{'button_main_hangup'}", -command => sub{dm::disconnect});
	$balloon->attach($disconnect_button, -balloonmsg => 'Disconnect immediatly by issuing "Down Cmd"') if $balloon;
	my $b2 = $frame->Button(-text => 'Graph', -command => sub{make_gui_graphwindow(30 * $secs_per_min, 200)});
	my $b3 = $frame->Button(-text => 'Exp-Graph', -command => sub{exp_make_gui_graphwindow()});
	
	$disconnect_button->pack(-expand => 1, -fill => 'x', -side => 'left') if $cfg_gui{'show_disconnect_button'};
#	$b2->pack(-expand => 1, -fill => 'x',  -side => 'left');
#	$b3->pack(-expand => 1, -fill => 'x',  -side => 'left') if defined &exp_make_gui_graphwindow;
	$frame->pack(-expand => 1, -fill => 'x');
    }
    $main_widget->repeat (1000, sub{update_gui()});
    $main_widget->repeat (1000, sub{dm::tick()});


    if ($dm::state == $dm::state_startup) {
	dm::state_trans_startup_to_offline ();
   }
    # debug aid
    if (0) {
	state_trans_offline_to_dialing ();
#	state_trans_dialing_to_online ();
    }

    $top->pack() if $top != $main_widget;
}

sub main_window_iconify () {
    $main_widget->iconify;
}
sub main_window_deiconify () {
    $main_widget->deiconify;
}

# config editor gui
=pod

=head2 NAME

mask_widget() - produce pairs of key/value-widgets

=head2 PARAMETERS and RESULT

=over 4

=item MASK_FRAME - Created widgets will be direct childs of it

=item ROW - Row on which our first new produced widget pair starts.

=item WIDGETS - Array to keep produced value widgets (Entry, Checkbox)

=item TYPES - Array holding type info strings ('text', 'flag', 'color', 'label')

=item KEYS - Array holding key strings (using for label names)

=item VALOC - Array holding value strings (will be used as defaults on value widgets)

=item RESULT - row-number after our last produced widget

=back


=head2 DESCRIPTION

=cut

sub mask_widget( $$$$$$ ) {
    my ($mask_frame, $row, $widgets, $types, $keys, $vals) = @_;
    for my $i (0..$#$keys) {
	my ($key, $val) = ($$keys[$i], $$vals[$i]);
	$val="" unless defined $val;
	db_trace("row:$row");
	$mask_frame->Label(-text => "$key")->grid(-row => $row, -column => 0, -sticky => "e");
	if ($$types[$i] eq 'text') {
	    my $entry = $mask_frame->Entry()->grid(-row => $row, -column => 1);
	    $entry->insert(0, $val);
	    $$widgets[$i] = $entry;
	} elsif ($$types[$i] eq 'optmenu') {
	    my $entry = $mask_frame->Entry()->grid(-row => $row, -column => 1);
	    $entry->insert(0, $val);
	    $$widgets[$i] = $entry;

=pod
	    my $b = $mask_frame->BrowseEntry(-label => "Label", -choices => Dialup_Cost::get_rate_names());
	    $b->grid(-row => $row, -column => 1);
	    $$widgets[$i] = $b;
=cut



	    $mask_frame->Optionmenu(-options => Dialup_Cost::get_rate_names(),
				    -command => sub { 
					$entry->delete(0, 'end');
					$entry->insert(0, shift @_);}
#				    -variable => \$var,
				    )->grid(-row => $row, -column => 0, -sticky => "e");
	} elsif ($$types[$i] eq 'flag') {
	    my $cb = $mask_frame->Checkbutton()->grid(-row => $row, -column => 1, -sticky => "w");
	    $cb->select if ($val == '1');
	    $$widgets[$i] = $cb;
	} elsif ($$types[$i] eq 'label') {
	    my $label = $mask_frame->Label(-text => "$val")->grid(-row => $row, -column => 1, -sticky => "w");
	    $$widgets[$i] = $label;
	} elsif ($$types[$i] eq 'color') {
	    my $entry = $mask_frame->Entry()->grid(-row => $row, -column => 1);
	    set_color_entry ($entry, $val);

	    $entry->insert(0, $val);
	    $$widgets[$i] = $entry;
	    $mask_frame->Button
		(-text => "$key", -command => sub
		 {
		     my $old_color = get_color_entry ($entry);
		     my $color = $mask_frame->chooseColor(-parent => $mask_frame,
							  -initialcolor => "$old_color");
		     if ($color) {
			 $entry->delete(0, 'end');
			 $entry->insert(0, "$color");
			 set_color_entry ($entry, $color);
		     }
		 } )->grid(-row => $row, -column => 0, -sticky => "ew");

	    # Toggling color preview in Entry widget using MousePress events
	    my ($sub_preview_on, $sub_preview_off);
	    $sub_preview_on = sub {
		set_color_entry ($entry, $entry->get());
		$entry->Tk::bind ('<ButtonPress>', $sub_preview_off);
	    };
	    $sub_preview_off = sub {
		$entry->configure (-fg => $mask_frame->cget('-fg'),
				   -bg => $mask_frame->cget('-bg'));
		$entry->Tk::bind ('<ButtonPress>', $sub_preview_on);
	    };
	    $entry->Tk::bind ('<ButtonPress>', $sub_preview_off);
	}
	$row++;
    }

    $mask_frame->pack(-side => 'top');
    db_trace ("gridSize: " . $mask_frame->gridSize);
    $row;
}

my @cfg__isp_cfg_cache;
my $cc=0;
sub pcfg_apply( $$$$ ) {
    my ($frame, $lb, $index, $widgets) = @_;
    my @config_values;

    # copy values from widgets to array @config_values
    foreach my $i (0..$#$widgets) {
	if ($pcfg_types[$i] eq 'text' or $pcfg_types[$i] eq 'optmenu') {
	    $config_values[$#config_values+1] = $$widgets[$i]->get;
	} elsif ($pcfg_types[$i] eq 'color') {
	    $config_values[$#config_values+1] = $$widgets[$i]->get;
	    set_color_entry ($$widgets[$i], $$widgets[$i]->get);
	} elsif ($pcfg_types[$i] eq 'flag') {
	    $config_values[$#config_values+1] = $$widgets[$i]->{'Value'};
	}
    }

    my $isp = $config_values[0];

    # note change in peer visibility to force building a new mainwindow
    $cc++ if (dm::get_isp_cfg($isp, $dm::cfg_active) != $config_values[$dm::cfg_active]);

    # update (overwrite) global configuration for this ISP
    # (widgets are currently in same order as global ISP config table is
    #  so we can just pass our value array to set_isp_cfg())
    dm::set_isp_cfg (\@config_values);

    # update our configuration cache to reflect change in global configuration made above
    foreach my $i (0..$#cfg__isp_cfg_cache) {
	my $r = $cfg__isp_cfg_cache[$i];
	if ($$r[$dm::cfg_isp] eq $isp) {
	    $cfg__isp_cfg_cache[$i] = \@config_values;
	}
    }
}

# TODO: TAB switching order
sub rcfg_make_window( $$$$$ ) {
  my ($parent, $rate, $matrix, $entries, $balloon) = @_;
  my $labels=$$matrix[0];
  my $balloons=$$matrix[2];
  my $fmts=$$matrix[1];
  my $start_matrix=3;
  my $rows = scalar @$matrix - $start_matrix;
  my $cols = scalar @$labels;
  my $top = $parent->Frame;
  my $table_frame = $top->Frame;
  $table_frame->pack(-side => 'top');
  $rcfg_current_col = $rcfg_current_row = 0;

  ## make table columns

  for (my $c=0; $c < $cols; $c++) {
    my @wids;
    $$entries[$c]=\@wids;
    # make column label (table head)
    my $label = $table_frame->Label(-text => $$labels[$c])->grid(-row => 0, -column => $c);
    # atach balloon help to table head
    $balloon->attach($label, -balloonmsg => $$balloons[$c]) if $balloon && $$balloons[$c];
  }

  foreach my $r ($start_matrix..$#$matrix) {
    my $wr=$r - $start_matrix;
    my $col_matrix= $$matrix[$r];

    for (my $c=0; $c < $cols; $c++) {
      my $wids=$$entries[$c];
      my $wid=0;
      # make row cells
      if ($$fmts[$c] =~ /^cstring:(\d+)/) {
	my $width=$1;
	$wid = $$wids[$wr] = $table_frame->Entry(-width => $width);
	$wid->insert(0, $$col_matrix[$c]);
	$wid->grid(-row => $r, -column => $c);
      } elsif (($$fmts[$c] =~ /^checkbox$/)) {
	$wid = $$wids[$wr] = $table_frame->Checkbutton();
	$wid->select if $$col_matrix[$c];
	$wid->grid(-row => $r, -column => $c);
      }
      my $curr_column=$c;
      $wid->bind('<FocusIn>' => sub { $rcfg_current_col = $curr_column; $rcfg_current_row = $wr; 
				      db_trace("$rcfg_current_col:$rcfg_current_row");
				    });
    }
  }

  foreach my $wr ($rows..$rows+5) {
    my $r=$wr + $start_matrix;
    for (my $c=0; $c < $cols; $c++) {
      my $wids=$$entries[$c];
      my $wid;
      # make row cells
      if ($$fmts[$c] =~ /^cstring:(\d+)/) {
	my $width=$1;
	$wid = $$wids[$wr] = $table_frame->Entry(-width => $width, -state => 'disabled');
	$wid->grid(-row => $r, -column => $c);
      } elsif (($$fmts[$c] =~ /^checkbox$/)) {
	$wid = $$wids[$wr] = $table_frame->Checkbutton(-state => 'disabled');
	$wid->grid(-row => $r, -column => $c);
      }
      my $curr_column=$c;
      $wid->bind('<FocusIn>' => sub { $rcfg_current_col = $curr_column; $rcfg_current_row = $wr; 
				      db_trace("$rcfg_current_col:$rcfg_current_row");
				    });
    }
  }

  my $button_frame = $top->Frame;
  $button_frame->pack(-side => 'bottom');
  $button_frame->Button(-text => 'Remove Row',
			-command => sub {
			  rcfg_delete_row ($matrix, \@rcfg_widgets, $rcfg_current_row);
			})->pack(-side => 'left');
  $button_frame->Button(-text => 'Insert Row',
			-command => sub {
			  rcfg_insert_row ($matrix, \@rcfg_widgets, $rcfg_current_row);
			})->pack(-side => 'left');
  $button_frame->Button(-text => 'Append Row',
			-command => sub {
			  rcfg_append_row ($matrix, \@rcfg_widgets);
			})->pack(-side => 'left');
  $button_frame->Button(-text => 'Save+Close',
			-command => sub {
			  rcfg_update_matrix($matrix, \@rcfg_widgets);
			  Dialup_Cost::set_pretty_rate ($rate, rcfg_parse_matrix ($matrix));
			  dm::save_cost_data();
			  $parent->destroy })->pack();
  $top;
}
## write matrix from window (symmetric to rcfg_make_window())
sub rcfg_update_matrix( $$ ) {
    my ($matrix, $widgets) = @_;
    my $labels=$$matrix[0];
    my $fmts=$$matrix[1];
    my $start_matrix=3;
    my $rows = scalar @$matrix - $start_matrix;
    my $cols = scalar @$labels;
    ## make table columns
    for (my $c=0; $c < $cols; $c++) {
      my $wids=$$widgets[$c];
      # make column cells
      foreach my $r ($start_matrix..$#$matrix) {
	my $row=$r - $start_matrix;
	if ($$fmts[$c] =~ /^cstring:(\d+)/) {
	  my $wid=$$wids[$row];
	  my $col_matrix= $$matrix[$r];
	  db_trace("wid=$wid");
	  $$col_matrix[$c] = $wid->get;
	} elsif (($$fmts[$c] =~ /^checkbox$/)) {
	  my $wid=$$wids[$row];
	  my $col_matrix= $$matrix[$r];
	  $$col_matrix[$c] = (defined $wid->{'Value'} and $wid->{'Value'}) ? 1 : 0;
	}
      }
    }
}

## create data table for cost preferece window (rcfg_make_window())
## 1st row are labels.  2nd row are data-type-IDs.  In 3rd row starts data.
sub rcfg_make_matrix( $ ) {
    my ($rate_name) = @_;
    my @labels = ($LOC{'win_rate_date_start'},
		  $LOC{'win_rate_date_end'},
		  $LOC{'win_rate_weekdays'},
		  $LOC{'win_rate_daytime_start'},
		  $LOC{'win_rate_daytime_end'},
		  $LOC{'win_rate_money_per_min'},
		  $LOC{'win_rate_secs_per_unit'},
		  $LOC{'win_rate_money_per_connect'},
		  $LOC{'win_rate_free_linkup'},
		  $LOC{'win_rate_overlay_rate'},
		  );
    my @balloons = ($LOC{'win_rate_date_start.help'},
		    $LOC{'win_rate_date_end.help'},
		    $LOC{'win_rate_weekdays.help'},
		    $LOC{'win_rate_daytime_start.help'},
		    $LOC{'win_rate_daytime_end.help'},
		    $LOC{'win_rate_money_per_min.help'},
		    $LOC{'win_rate_secs_per_unit.help'},
		    $LOC{'win_rate_money_per_connect.help'},
		    $LOC{'win_rate_free_linkup.help'},
		    $LOC{'win_rate_overlay_rate.help'},
		    );
    my @matrix;
    $matrix[$#matrix+1] = \@labels;
    $matrix[$#matrix+1] = ['cstring:10','cstring:10','cstring:10','cstring:8',
			   'cstring:8','cstring:5','cstring:4','cstring:4', 'checkbox', 'checkbox'];
    $matrix[$#matrix+1] = \@balloons;
    my $rate = Dialup_Cost::get_pretty_rate ($rate_name);
    foreach my $r (@$rate) {
	my @sub_entries = ("","","","","","","","");
	my $r0 = $$r[0];

	if (ref $$r0[0]) {
	    my $r00 = $$r0[0];
	    $sub_entries[0] = ($$r00[0] == 0) ? "0" : substr (dm::format_ltime ($$r00[0]), 0, 19);
	    $sub_entries[1] = ($$r00[1] == 0) ? "0" : substr (dm::format_ltime ($$r00[1]), 0, 19);
	}
	if (ref $$r0[1]) {
	    my $r01 = $$r0[1];
	    foreach my $wday (@$r01) {
		$sub_entries[2] .= "$wday";
	    }
	}
	if (ref $$r0[2]) {
	    my $r02 = $$r0[2];
	    $sub_entries[3] = dm::format_day_time ($$r02[0]);
	    $sub_entries[4] = dm::format_day_time ($$r02[1]);
	}
	my $r1 = $$r[1];
	$sub_entries[5] = sprintf ("%.2f", ($$r1[0] * 60) / $$r1[1]);
	$sub_entries[6] = $$r1[1];
	$sub_entries[7] = $$r1[3];
	$sub_entries[8] = ($$r1[2] == 0);
	$sub_entries[9] = ($$r1[4] == 2);

	$matrix[$#matrix+1]=\@sub_entries;
    }
#test#    rcfg_parse_matrix (\@matrix);
    \@matrix;
}

sub rcfg_matrix_insert_row ( $$ ) {
  my ($matrix, $index) = @_;
  foreach my $i (reverse($index..$#$matrix)) {
    $$matrix[$i+1]=$$matrix[$i];
  }
  $$matrix[$index]=["","","","","","",0,0]; # default matrix row
}
sub rcfg_matrix_delete_row ( $$ ) {
  my ($matrix, $index) = @_;
  foreach my $i ($index..$#$matrix-1) {
    $$matrix[$i]=$$matrix[$i+1];
  }
  --$#$matrix;
}

sub rcfg_insert_row( $$$ ) {
  my ($matrix, $widgets, $index) = @_;
  my $start_matrix=3;
  rcfg_matrix_insert_row ($matrix, $index + $start_matrix);
  my $labels=$$matrix[0];
  my $fmts=$$matrix[1];
  my $rows = scalar @$matrix - $start_matrix;
  my $cols = scalar @$labels;
  ## make table columns
  for (my $c=0; $c < $cols; $c++) {
    my $wids=$$widgets[$c];
    db_trace("insert_row \$index=$index \$#\$wids=$#$wids");
    # make column cells
    foreach my $wr (reverse($index..$#$wids-1)) {
#      my $mr=$wr + $start_matrix;
      my $src_wid=$$wids[$wr];
      my $tgt_wid=$$wids[$wr+1];
      next if ($src_wid->cget('-state') eq 'disabled');
      $tgt_wid->configure(-state => 'normal');
      if ($$fmts[$c] =~ /^cstring:(\d+)/) {
	$tgt_wid->delete ('0', 'end');
	$tgt_wid->insert ('0', $src_wid->get);
	$src_wid->delete ('0', 'end');
      } elsif (($$fmts[$c] =~ /^checkbox$/)) {
	if ($src_wid->{'Value'}) {
	  $tgt_wid->select;
	} else {
	  $tgt_wid->deselect;
	}
	$src_wid->deselect;
      }
    }
  }
  # adjust focus
  my $wids = $$widgets[$rcfg_current_col=0];
  my $wid=$$wids[$rcfg_current_row=$index];
  $wid->focus;
}

sub rcfg_append_row( $$ ) {
  my ($matrix, $widgets) = @_;
  my $start_matrix=3;
  my $index = $#$matrix - $start_matrix + 1;
  rcfg_matrix_insert_row ($matrix, $index + $start_matrix);
  my $labels=$$matrix[0];
  my $fmts=$$matrix[1];
  my $rows = scalar @$matrix - $start_matrix;
  my $cols = scalar @$labels;
  ## make table columns
  for (my $c=0; $c < $cols; $c++) {
    my $wids=$$widgets[$c];
    db_trace("insert_row \$index=$index \$#\$wids=$#$wids");
    # make column cells
    my $tgt_wid=$$wids[$index];
    $tgt_wid->configure(-state => 'normal');
  }
  my $wids = $$widgets[$rcfg_current_col=0];
  my $wid=$$wids[$rcfg_current_row=$index];
  $wid->focus;
}

sub rcfg_delete_row( $$$ ) {
  my ($matrix, $widgets, $index) = @_;
  my $start_matrix=3;
  rcfg_matrix_delete_row ($matrix, $index + $start_matrix);
  my $labels=$$matrix[0];
  my $fmts=$$matrix[1];
  my $rows = scalar @$matrix - $start_matrix;
  my $cols = scalar @$labels;
  ## make table columns
  for (my $c=0; $c < $cols; $c++) {
    my $wids=$$widgets[$c];
    db_trace("insert_row \$index=$index \$#\$wids=$#$wids");
    # make column cells
    foreach my $wr ($index..$#$wids-1) {
#      my $mr=$wr + $start_matrix;
      my $src_wid=$$wids[$wr+1];
      my $tgt_wid=$$wids[$wr];
      $tgt_wid->configure(-state => 'disabled') if ($src_wid->cget('-state') eq 'disabled');
      if ($$fmts[$c] =~ /^cstring:(\d+)/) {
	$tgt_wid->delete ('0', 'end');
	$tgt_wid->insert ('0', $src_wid->get);
	$src_wid->delete ('0', 'end');
      } elsif (($$fmts[$c] =~ /^checkbox$/)) {
	if ($src_wid->{'Value'}) {
	  $tgt_wid->select;
	} else {
	  $tgt_wid->deselect;
	}
	$src_wid->deselect;
      }
    }
  }
  # adjust focus
  for (;$rcfg_current_row; --$rcfg_current_row) {
    my $wids = $$widgets[$rcfg_current_col];
    my $wid=$$wids[$rcfg_current_row];
    if ($wid->cget('-state') ne 'disabled') {
      $wid->focus;
      last;
    }
  }
}

# read back edited cost data
sub rcfg_parse_matrix( $ ) {
    my ($matrix) = @_;

    my @result;
    my $row_idx=-3;
    foreach my $r (@$matrix) {
	next if ($row_idx++ < 0); # skip header and type-definition
	my @res_cond=(0, 0, 0);

	if ($$r[0] ne '') {
	    my $start = ($$r[0] eq "0") ? 0 : dm::parse_ltime ($$r[0]);
	    my $end = ($$r[1] eq "0") ? 0 : dm::parse_ltime ($$r[1]);
	    db_trace ("start: $start end: $end");
	    $res_cond[0] = [ $start, $end ];
	}
	if ($$r[2] ne "") {
	    my $str = $$r[2];
	    my @wdays;
	    while ($str =~ /([0-6])/g) {
		$wdays[$#wdays+1]= $1 * 1;
	    }
	    db_trace ("wdays: @wdays");
	    $res_cond[1] = \@wdays;
	}
	if ($$r[3] ne "") {
	    my $start_time = dm::parse_day_time ($$r[3]);
	    my $end_time = dm::parse_day_time ($$r[4]);
	    db_trace ("start_time: $start_time end_time: $end_time");
	    $res_cond[2] = [ $start_time, $end_time ];
	}

	my $pfg_per_connect = $$r[7] * 1;
	my $secs_per_unit = $$r[6] * 1;
	my $pfg_per_unit = ($$r[5] / 60) * $secs_per_unit;
	my $f1 = ($$r[8] == 0) ? 1 : 0;
	my $f2 = ($$r[9] == 1) ? 2 : 1;

	next if ($secs_per_unit < 1); # XXX

	db_trace ("pfg_per_unit: $pfg_per_unit  secs_per_unit: $secs_per_unit  pfg_per_connect: $pfg_per_connect");
	my @res = ( \@res_cond, [ $pfg_per_unit, $secs_per_unit, $f1, $pfg_per_connect, $f2 ] );
	$result[$#result+1]=\@res;
#test#	print STDERR Dialup_Cost::write_list (\@res); 
    }
#test# my %tmp=(xxx => \@result); print STDERR Dialup_Cost::write_data (\%tmp); 
    \@result;
}

sub pcfg_start_rcfg_new( $ ) {
    my ($rate_name) = @_;
    my $win = $main_widget->Toplevel;
    my $balloon = $cfg_gui{'balloon_help'} ? $win->Balloon() : 0;
    $win->title("$APPNAME: cost for rate <$rate_name>");
    undef @rcfg_widgets;
    rcfg_make_window ($win, $rate_name, rcfg_make_matrix ($rate_name), \@rcfg_widgets, $balloon)->pack();
}

sub pcfg_start_rcfg( $$ ) {
    my ($lb, $index) = @_;
    my $isp = $lb->get($index);
    my $isp_rate = dm::get_isp_tarif ($isp);
    pcfg_start_rcfg_new ($isp_rate);
};

sub pcfg_update_gadgets( $$ ) {
    my ($idx, $gadgets) = @_;
    my $cfg = $cfg__isp_cfg_cache[$idx];
    for (my $i=0; $i < $dm::cfg_SIZE; $i++) {
#	$$cfg[$i]=$$gadgets[$i]->get();
	if ($pcfg_types[$i] eq 'text' or $pcfg_types[$i] eq 'optmenu') {
	    $$gadgets[$i]->delete(0, 'end');
	    $$gadgets[$i]->insert(0, $$cfg[$i]);
	} elsif ($pcfg_types[$i] eq 'color') {
	    $$gadgets[$i]->delete(0, 'end');
	    $$gadgets[$i]->insert(0, $$cfg[$i]);
	    set_color_entry ($$gadgets[$i], $$cfg[$i]);
	} elsif ($pcfg_types[$i] eq 'flag') {
	    if ($$cfg[$i]) { $$gadgets[$i]->select; } else { $$gadgets[$i]->deselect; }
	}
    }
}

sub pcfg_editor_window( $$ ) {
    my ($xmax, $ymax) = @_;	#(30 * $secs_per_min, 200);
    my $win=$main_widget->Toplevel;
    $win->title("$APPNAME: Config");

    my $frame1 = $win->Frame;
    my $box = $frame1->Listbox(-relief => 'sunken',
			       -width => -1, # Shrink to fit
			       -height => 10,	
			       -selectmode => 'browse',
			       -setgrid => 1);

    my $scroll = $frame1->Scrollbar(-command => ['yview', $box]);
    my $item_entry = $win->Entry();

    my $frame3 = $win->Frame;
    require Tk::Dialog;
    my $dialog = $frame3->Dialog(-text => 'Really delete peer?',
				 -title => 'tkdialup: Confirm', -default_button => 'No',
				 -buttons => [qw/Yes No/]);
    my $item_del_bt = $frame3->Button(-text => 'Delete Peer',
    -command => sub {
	my $idx = $box->index('active');
	my $isp = $dm::isps[$idx];
	db_trace("idx: $idx isp:$isp");
	if ($dialog->Show eq "Yes") {
	    $cc++ if (dm::get_isp_flag_active ($isp));
	    $box->delete($idx);
	    $box->see($idx);
	    $box->selectionSet($idx);
	    splice (@cfg__isp_cfg_cache, $idx, 1);
	    delete $widgets{$isp};
	     dm::remove_isp_by_index ($idx);
	    pcfg_update_gadgets ($box->index('active'), \@pcfg_widgets);
	}
	});

    my $item_add_bt = do
      {
	require Tk::DialogBox;
	my $dialog = $frame3->DialogBox(-title => "tkdialup: New Peer", -buttons => ["OK", "Cancel"]);
	#	$dialog->add(Widget, args);
	$dialog->add('Label', -text => "Please enter a name")->pack();
	my $add_name = $dialog->add('Entry')->pack();

	my $button = $frame3->Button
	  (-text => 'New Peer',
	   -command => sub {
	     if ($dialog->Show eq "OK" and $add_name->get and not defined ($dm::isp_cfg_map{$add_name->get}) ) {
	       my $isp = $add_name->get;
	       my $lbidx = $box->insert ('end', $isp);
	       $box->selectionClear(0, 'end');
	       $box->activate('end');
	       $box->see('end');
	       $box->selectionSet('end');

	       my @config_values=("$isp","pon $isp","poff $isp","$isp","Black","FLAT", "1");
	       $cfg__isp_cfg_cache[$#cfg__isp_cfg_cache+1]=\@config_values;
	       $dm::isps[$#dm::isps+1]=$isp;
	       dm::set_isp_cfg (\@config_values);
	       pcfg_update_gadgets ($box->index('active'), \@pcfg_widgets);
	       $cc++;
	     }
	   });
	$button;
      };
    my $frame4 = $win->Frame;
    my $edit_bt = $frame4->Button(-text => 'Edit Rate', -command => sub{pcfg_start_rcfg($box, $box->index('active'))});
    my $add_rate_bt = do {
      require Tk::DialogBox;
      my $dialog = $frame3->DialogBox(-title => "tkdialup: New Rate", -buttons => ["OK", "Cancel"]);
      $dialog->add('Label', -text => "Please enter a name")->pack();
      my $name = $dialog->add('Entry')->pack();
      my $button = $frame4->Button
	(-text => 'New Rate',
	 -command => sub {
	   if ($dialog->Show eq "OK" and $name->get
	       and not defined (my $tem = Dialup_Cost::get_rate($name->get))) {
	     pcfg_start_rcfg_new ($name->get);
	   }
	 });
      $button;
    };


    my $frame2 = $win->Frame;
    my $close_or_restart = sub { undef @cfg__isp_cfg_cache;
				 if ($cc) {
				     $cc=0;
				     $app_has_restarted=1;
				     $win->destroy;
				     $main_widget->destroy;
				 } else { $win->destroy }};

    my $exit_bt = $frame2->Button(-text => 'Close', -command => $close_or_restart);
    my $save_bt = $frame2->Button(-text => 'Save+Close', -command => sub{ dm::save_config(); &$close_or_restart; });

    foreach (@dm::isps) {
	$box->insert('end', $_);
	my @cfg;
	$cfg__isp_cfg_cache[$#cfg__isp_cfg_cache+1] = \@cfg;
	for (my $i=0; $i < $dm::cfg_SIZE; $i++) {
	    $cfg[$#cfg+1] =  dm::get_isp_cfg ($_, $i);
	}
    }

    $box->configure(-yscrollcommand => ['set', $scroll]);

    $frame1->pack(-fill => 'both', -expand => 1);
    $box->pack(-side => 'left', -fill => 'both', -expand => 1);
    $scroll->pack(-side => 'right', -fill => 'y');
#$item_entry->pack(-fill => 'x');

    {
	my $isp = $box->get(0);
	my $top = $win->Frame;
	my $mask_frame = $top->Frame;
	my $row = mask_widget ($mask_frame, 0, \@pcfg_widgets, \@pcfg_types, \@pcfg_labels, $dm::isp_cfg_map{$isp});
#exp#	$entries[0]->configure(-invcmd => 'bell', -vcmd => sub { 0; }, -validate => 'focusout');
	$mask_frame->Label(-text => "(Rates:)")->grid(-row => $row, -column => 0);
	my @sorted_rate_names = do { my $ref = Dialup_Cost::get_rate_names(); sort @$ref };
	$mask_frame->Optionmenu(-options => \@sorted_rate_names,
				-command => sub { 
				    $pcfg_widgets[$dm::cfg_tarif]->delete(0, 'end');
				    $pcfg_widgets[$dm::cfg_tarif]->insert(0, shift @_);}
#				    -variable => \$var,
				)->grid(-row => $row, -column => 1, -sticky => "e");
	my $frame1 = $top->Frame;
#XXX#	$frame1->Button(-text => 'Cancel', -command => sub{ pcfg_update_gadgets ($box->index('active'), \@pcfg_widgets) })->pack();
	$frame1->Button(-text => 'Apply',
			-command => sub{pcfg_apply($top, $box, 0, \@pcfg_widgets)})->pack(-expand => 1, -fill => 'both', -side => 'right');
	$frame1->pack(-fill => 'x');
	$top->pack(-expand => 1, -fill => 'both');
    }

    $frame3->pack(-fill => 'x');
#    $frame4->pack(-fill => 'x');
#$view_bt->pack(-side => 'bottom');
    $item_add_bt->pack(-side => 'right');
    $item_del_bt->pack(-side => 'left');
    # Rate:
    $add_rate_bt->pack(-side => 'right');
    $edit_bt->pack(-side => 'left');

    $frame2->pack(-fill => 'x');
    $save_bt->pack(-side => 'right');
    $exit_bt->pack(-side => 'left');

    pcfg_update_gadgets ($box->index('active'), \@pcfg_widgets);
    $box->Tk::bind ('<KeyPress>', sub { pcfg_update_gadgets ($box->index('active'), \@pcfg_widgets) });
    $box->Tk::bind ('<ButtonRelease>', sub { pcfg_update_gadgets ($box->index('active'), \@pcfg_widgets) });
    $box->focus;
}

sub color_cfg_editor_window( $$ ) {
    my ($xmax, $ymax) = @_;
    my $win=$main_widget->Toplevel;
    $win->title("$APPNAME: Graph Colors");

    my @widgets;
    my @types = ('color', 'color', 'color', 'text');
    my @keys = ('Background Color', 'Ruler Color', 'Ruler2 Color', '(Language {de,en})');
    my @cfg_keys = ('graph_bgcolor', 'graph_nrcolor', 'graph_ercolor', 'lang');
    my @vals;
    my @refs;
    my @defaults;
    foreach my $i (0..$#cfg_keys) {
	if (defined $cfg_gui{$cfg_keys[$i]}) {
	    $vals[$i] = $cfg_gui{$cfg_keys[$i]};
	    $refs[$i] = \$cfg_gui{$cfg_keys[$i]};
	    $defaults[$i] = $cfg_gui_default{$cfg_keys[$i]};
	}
    }
    my $top = $win->Frame;
    my $mask_frame = $top->Frame;
    mask_widget ($mask_frame, 0, \@widgets, \@types, \@keys, \@vals);
    $mask_frame->pack(-expand => 1, -fill => 'both');

    my $frame1 = $top->Frame;
    $frame1->Button(-text => 'Cancel', -command => sub { $win->destroy(); })->pack(-side => 'left' );
    $frame1->Button(-text => 'Apply',
		    -command => sub
		    { foreach my $i (0...$#refs) {
			if ($types[$i] eq 'color' or $types[$i] eq 'text') {
			    my $ref = $refs[$i]; 
			    $$ref = $widgets[$i]->get();
			    if ($types[$i] eq 'color') {
				set_color_entry ($widgets[$i], $widgets[$i]->get());
			    }
			}
		    }
		      if ($current_applang ne $cfg_gui{'lang'}) {
			  $app_has_restarted=1;
			  $main_widget->destroy;
		      } else {
			  $win->destroy ();
		      }
		    })->pack(-side => 'right');
    $frame1->Button(-text => 'Default',
		    -command => sub
		    { foreach my $i (0..$#cfg_keys) {
			my $ref = $refs[$i];
			my $val = $defaults[$i];
			my $wid = $widgets[$i];
			#$$ref = $val;
			if ($types[$i] eq 'color' or $types[$i] eq 'text') {
			    $wid->delete(0, 'end');
			    $wid->insert(0, "$val");
			    if ($types[$i] eq 'color') {
				set_color_entry ($wid, $val);
			    }
			}
		    }
		  })->pack();
    $frame1->pack(-fill => 'x');
    $top->pack(-expand => 1, -fill => 'both');
}

sub rcfg_editor_window( $$ ) {
    my ($xmax, $ymax) = @_;	#(30 * $secs_per_min, 200);
    my $win=$main_widget->Toplevel;
    $win->title("$APPNAME: Rate Config");

    # Rate Optionmenu
    my $frame1 = do {
      my $current_rate="";
      my $frame = $win->Frame(-relief => 'flat', -bd => '8');

      # Choose Rate Menu
      my $frame1 = $frame->Frame;
      $frame1->Label(-text => "Rate: ")->pack(-fill => 'x', -side => 'left', -expand => 'both');
      my $update_options = sub { my $wid=shift;
				 my @sorted_rate_names = do { my $ref = Dialup_Cost::get_rate_names(); sort @$ref };
				 $wid->configure(-options => \@sorted_rate_names);
				 db_trace("update_options()");
			       };
      my $optmenu = $frame1->Optionmenu(-variable => \$current_rate)->pack (-fill => 'x', -side => 'left');

      &$update_options ($optmenu);
      my $frame2 = $frame->Frame;
      # Edit Rate Button
      my $edit_rate = $frame2->Button
	(-text => "Edit",
	 -command => sub { pcfg_start_rcfg_new ($current_rate) },
	)->pack(-fill => 'x', -side => 'left', -expand => 'both');
      # Delete Rate Button
      require Tk::Dialog;
      my $delete_rate = $frame2->Button
	(-text => "Delete",
	 -command => sub {
	   my $delete_rate_dialog = $frame2->Dialog(-text => "[$current_rate]\nReally delete rate?",
						    -title => 'tkdialup: Confirm', -default_button => 'No',
						    -buttons => [qw/Yes No/]);
	   if ($delete_rate_dialog->Show eq "Yes") {
	     Dialup_Cost::delete_rate ($current_rate);
	     &$update_options ($optmenu);
	   }
	 },
	)->pack(-fill => 'x', -side => 'left', -expand => 'both');
      # New Rate Button
      my $new_rate = do {
	require Tk::DialogBox;
	my $dialog = $frame2->DialogBox(-title => "tkdialup: New", -buttons => ["OK", "Cancel"]);
	$dialog->add('Label', -text => "Please enter a name")->pack();
	my $name = $dialog->add('Entry')->pack();
	my $button = $frame2->Button
	  (-text => 'New',
	   -command => sub {
	     if ($dialog->Show eq "OK" and $name->get
		 and not defined (my $tem = Dialup_Cost::get_rate($name->get))) {
	       Dialup_Cost::set_pretty_rate($name->get, []);
	       &$update_options ($optmenu);
	       pcfg_start_rcfg_new ($name->get);
	     }
	   });
	$button;
      };
      $new_rate->pack(-fill => 'x', -side => 'left', -expand => 'both');
      # -----------------
      $frame1->pack(-fill => 'x');
      $frame2->pack(-fill => 'x', -expand => 'both');
      $frame;
    };

    my $frame4 = $win->Frame;
    my $frame2 = $win->Frame (-relief => 'sunken', -bd => '2');
    my $exit_bt = $frame2->Button (-text => 'Cancel+Close', -command => sub { $win->destroy });
    my $save_bt = $frame2->Button (-text => 'Save+Close',
				   -command => sub{ dm::save_cost_data();
						    $win->destroy });




    $frame1->pack(-fill => 'x');

    $frame4->pack(-fill => 'x');
    $frame2->pack(-fill => 'x');
    $save_bt->pack(-side => 'right');
    $exit_bt->pack(-side => 'left');

}

########################################################################################
sub read_config_old( $$$ ) {
    my ($file, $section, $cfg_hash) =@_;
    my $config_tag=$$cfg_hash{'.config_tag'};
    my $config_version=$$cfg_hash{'.config_version'};
    my $cfg_default_hash=$$cfg_hash{'.config_default'};
    my $result=0;
    if (open IN, ("$file")) {
	while (<IN>) {
	    if (m/^\<$section\s+version=[\"]([^\"]+)[\"]\s*\>/) {
		my $current_version="$1";
		while (<IN>) {
		    last if (m/\<\/$section\s*\>/);
		    next if ($current_version ne $config_version);
		    if (/^\<$config_tag /) {
			$result++;
			while (m/\b([a-z_]+)\=["']([^\"\']*)['"]/g) {
			    my ($key, $val) = ($1, dm::unescape_string ($2));
			    $$cfg_hash{"$key"} = $val if defined $$cfg_default_hash{$key};
			    db_trace("key=<$key> val=<$val>");
			}
		    }
		}
	    }
	}
	close IN;
	$result } else { 0 }
}
sub read_config( $$$ ) {
    my ($file, $section, $cfg_arg) =@_;
    my $config_version=$$cfg_arg{'.config_version'};
    my $result=0;

    if (open IN, ("$file")) {
	while (<IN>) {
	    if (m/^\<$section\s+version=[\"]([^\"]+)[\"]\s*\>/) {
		my $current_version="$1";
		while (<IN>) {
		    last if (m/\<\/$section\s*\>/);
		    next if ($current_version ne $config_version);
		    #-----------------------------
		    if (/^\<([a-z\-_]+) /) {
			my $config_tag=$1;
			my $cfg_hash=$$cfg_arg{$config_tag};
			my $cfg_default_hash=$$cfg_hash{'.config_default'};
			$result++;
			while (m/\b([a-z_]+)\=["']([^\"\']*)['"]/g) {
			    my ($key, $val) = ($1, dm::unescape_string ($2));
			    $$cfg_hash{"$key"} = $val if defined $$cfg_default_hash{$key};
			    db_trace("key=<$key> val=<$val>");
			}
		    }
		    #-------------------------------
		}
	    }
	}
	close IN;
	$result } else { 0 }
}

sub restore_config () {
    read_config ($cfg_file_usr, "tkdialup-config", \%cfg_tkdialup ) or
	read_config ($cfg_file, "tkdialup-config", \%cfg_tkdialup);
}

sub write_config( $ ) {
    my ($file) =@_;
    if (open OUT, (">$file")) {
	my $line="";
	my $count=0;
	while (my ($key, $val) = each (%cfg_gui)) {
	    if ("$cfg_gui_default{$key}" ne $val) {
		$line .= "$key='" . dm::escape_string ($val) . "' ";
		db_trace ("key=<$key> val=<$val> count=<$count>");
	    }
	}
	if ($line) {
	    print OUT '<gui ' . $line . "/>\n";
	}
	close OUT;
	1;
    } else {
	0;
    }
}

sub save_config () {
  dm::write_config ($cfg_file_usr, "tkdialup-config", \%cfg_tkdialup);
}

sub read_locale( $ ) {
# read in locale file (see ./locale-de for a german locale file)
    my $lang=shift;
    if (open (LOC, "$progdir/locale-$lang")) {
	my $line=0;
	while (<LOC>) {
	    ++$line;
	    if (/^wday_names\s*=\s*(\w+)\s+(\w+)\s+(\w+)\s+(\w+)\s+(\w+)\s+(\w+)\s+(\w+)\s+$/) {
		@wday_names=($1, $2, $3, $4, $5, $6, $7); 
	    } elsif (/^([a-z_.]+)\s*=\s*(.+)\s*$/) {
		my $key=$1;
		my $val=$2;
		if (defined $LOC{$key}) {
		    $LOC{$key}=dm::unescape_string($val);
		} else {
		    print STDERR "$progdir/locale-$lang:$line: Unknown configuration key <$1>\n";
		}
	    }
	}
	close LOC;
    }
}

sub init_locale () {
@wday_names=('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
%LOC=
(
 'language_name' => 'English',
#---- File Menu
 'menu_file' => "File",
 'menu_file_hangup_now' => "Hangup now",
 'menu_file_hangup_now.help' => 'Disconnect immediatly by issuing "Down Cmd"',
 'menu_file_hangup_defer' => "Hangup later",
 'menu_file_hangup_defer.help' => 'Disconnect just before the current unit would end',
 'menu_file_save' => "Save Configuration",
 'menu_file_save.help' => 'Keep all configuration changes permanently',
 'menu_file_quit' => "Quit",
 'menu_file_quit.help' => 'Disconnect and terminate this "tkdialup" process immediatly.',
#---- Edit Menu
 'menu_edit' => "Edit",
 'menu_edit_options' => "Options",
 'menu_edit_options.help' => 'Change Programm settings',
 'menu_edit_peer_options' => "Peer Options",
 'menu_edit_peer_options.help' => 'Run a configuration editor. Its not full implemented yet
You can examine a rate but you cannot edit a rate yet.',
 'menu_edit_rate_options' => "Rate Options",
 'menu_edit_rate_options.help' => 'Config Editor to create, edit and delete rates',
 'menu_edit_graph_options' => "Graph Options",
 'menu_edit_graph_options.help' => 'Edit  background and ruler colors of graph window',
#---- View Menu
 'menu_view' => "View",
 'menu_view_graph' => "Graph",
 'menu_view_graph.help' => 'Show time/money graphs of all active peers',
 'menu_view_clock' => "Show clock",
 'menu_view_clock.help' => 'Show digital clock',
 'menu_view_progress_bar' => "Progress bar",
 'menu_view_progress_bar.help' => "Show progress bar to display cost unit",
 'menu_view_disconnect_button' => "Disconnect button",
 'menu_view_disconnect_button.help' => "Provide disconnect button",
 'menu_view_stat' => "Statistic ...",
 'menu_view_stat.help' => 'Show a time/money history list for this user',
 'button_main_hangup' => "Hangup",
#---- Help Menu
 'menu_help' => "Help",
 'menu_help_about' => "About ...",
 'menu_help_about.help' => 'Show information about this program and its author',
 'menu_help_balloon_help' => "Mouse Pointer Help",
 'menu_help_balloon_help.help' => 'Toggle showing balloon help',
#---- Rate Window
 'win_rate_date_start' => 'Start Date',
 'win_rate_date_start.help' => 'Date when this rate became vaild (may be empty if next field is empty too)',
 'win_rate_date_end' => 'End Date',
 'win_rate_date_end.help' => 'Date when this rate became or will become invalid',
 'win_rate_weekdays' => 'Weekdays',
 'win_rate_weekdays.help' => 'Set of numbers (0..6) representing weekdays (Sun..Sat)',
 'win_rate_daytime_start' => 'Start Time',
 'win_rate_daytime_start.help' => 'Daytime on which this rate becomes valid (may be empty if next field is empty too)',
 'win_rate_daytime_end' => 'End Time',
 'win_rate_daytime_end.help' => 'Daytime on which tis rate becomes invalid',
 'win_rate_money_per_min' => 'M/min',
 'win_rate_money_per_min.help' => 'Payment in money per minute (not per unit!)', 
 'win_rate_secs_per_unit' => 'secs/unit',
 'win_rate_secs_per_unit.help' => 'Length of a unit in seconds',
 'win_rate_money_per_connect' => 'M/Conn.',
 'win_rate_money_per_connect.help' => 'Payment per connection (usually 0)',
 'win_rate_free_linkup' => 'FL',
 'win_rate_free_linkup.help' => 'Free DialUp (Paying starts not before PPP connection is up)',
 'win_rate_overlay_rate' => 'OR',
 'win_rate_overlay_rate.help' => 'Overlay Rate (this may be a additional payment with a different unit length)',
#--- Main Window
 'win_main_start' => "Start",
 'win_main_start.help' => "Hit a Button to Connect a Peer",
 'win_main_money' => "Money",
 'win_main_money.help' => "Real Time Money Counter",
 'win_main_rate' => "Rate",
 'win_main_rate.help' => "Money per Minute",
#---
 );
}



##--- Main
@dm::commands_on_startup = ();
@dm::commands_before_dialing = (\&clear_gui_counter, \&update_gui_dialing);
@dm::commands_on_connect = (\&main_window_iconify, \&update_gui_online);
@dm::commands_on_connect_failure = (\&update_gui_failure, \&clear_gui_counter);
@dm::commands_on_disconnect = (\&main_window_deiconify, \&update_gui_offline, \&update_gui_counter, \&update_progress_bar);

$dm::time_correction_offset = $ENV{"TKD_TIME_OFFSET"} if defined $ENV{"TKD_TIME_OFFSET"}; # MS-Windows9x

restore_config ();

#read_config_old((-e $cfg_file_usr) ? $cfg_file_usr : $cfg_file);
# ???-bw/31-Aug-00 Is it allowed to restart Tk?
while ($app_has_restarted) {
  $app_has_restarted=0;
  if ($current_applang ne $cfg_gui{'lang'}) {
    $current_applang=$cfg_gui{'lang'};
    init_locale ();
    read_locale ($cfg_gui{'lang'});
  }

  make_gui_mainwindow();
  MainLoop;
}
