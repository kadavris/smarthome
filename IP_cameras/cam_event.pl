#!/bin/perl
# Written by Andrej Pakhutin (pakhutin at gmail)
# This is the part of segmented rtsp streams surveillance utility set.
# This particular module is for event processing from PIR or other kind of security sensors.
# It should have permissions to browse and link the camera recordings made by companion cam_service.
# Also it may be started as a deamon, listening for events from MQTT server.
#use re 'debugcolor';
use warnings;
use strict;
use Getopt::Long;
use File::Path qw(make_path);
use File::Basename;
use Carp;
use Net::MQTT::Simple;#::SSL;

my %cams;
my %o; # options

my $config_path = 'cam_event.config'; # default
my $debug = 0; # screen output is not suppressed
my $mqtt; # used as mqtt daemon mode flag/object if set
my $show_help = 0;

####################################################
# these are (re)initialized within init() call:
my @cams_capture; # cam names to rec from
my $event_id = ''; # name of the event that will be added to file name
my $event_start = time; # base for snap counts
my $log = 0; # no log will be produced
my $persistent; # the recordings will be synced on the -p=on until the call with -p=off with the same event ID will be made
my $snap_time; # (seconds) will snap so many records from before and after current

init();
####################################################

GetOptions (
  'c=s' => \$config_path,
  'd'   => \$debug,
  'e=s' => \$event_id,
  'h'   => \$show_help,
  'l'   => \$log,
  'm'   => \$mqtt,
  'p=s' => \$persistent,
  's=i' => \$snap_time,
) or die "GetOptions: $!";

umask 0007;

load_config( $config_path );

# --- MQTT ---
my %mqtt_pers_timeouts; # persistent recording mode t/o
defined( $mqtt ) and mqtt_run(); # no return from here
# --- MQTT ---

if ( ( ! $persistent && $#ARGV == -1 ) || $show_help )
{
  help();
}

@ARGV and @cams_capture = ( @ARGV );

main();

####################################################
####################################################
sub main
{
  #my $last_call_file_prefix = "/tmp/cam-event.last_call.";
  #my $last_call_ts = 0;

  my $persistent_flag = sprintf ( $o{ 'persistent flag template' }, $event_id );

  my %out_templates; # prefix for link&sync files
  my %out_index; # { cam name } = index for output/linked files. goes in range of 0..N($snap_time);
  my %old_recs; # will hold the array of old records names to link them in sequence

  $o{ 'events dir' } .= '/' . get_times('d');

  make_path( $o{ 'events dir' } );

  if ( defined( $persistent ) )
  {
    $persistent = lc $persistent;

    if( $persistent eq 'on' ) # touch it
    {
      touch_file( $persistent_flag, $$ ) or croak;
    }

    else # OFF - the sync process will stop when it sees the flag is gone
    {
      $debug and print "- [$$] removed $persistent_flag\n";
      unlink $persistent_flag;

      exit(0);
    }
  } # if ( defined( $persistent ) )

  ####################################################
  # initializing
  ####################################################
  for my $cam_id ( @cams_capture )
  {
    if ( ! exists $cams{ $cam_id } )
    {
      print STDERR "!ERROR! invalid camID: $cam_id. args: ", join(', ', @ARGV);
      next;
    }

    # constructing saved recs file names
    my $out_file = $o{ 'events dir' } . '/' . $cam_id;
    $event_id ne '' and $out_file .= '-{' . $event_id . '}';
    $out_file .=  '-%ts%_%index%'; # %ts for timestamp. the index will be file seq number
    $out_file .= $o{ 'records ext' };

    my $ts = get_times( 'dt' );
    $out_file =~ s/%ts%/$ts/g;

    $out_templates{ $cam_id } = $out_file;

    $debug and print "> [$$] Cam $cam_id will be synced to $out_file\n";
  } # for my $cam_id ( @cams_capture )

  ####################################################
  # now finding recent files to link and sync
  # files are sorted in the 'most recent - first' order.
  ####################################################
  chdir $o{ 'recent dir' } or croak "chdir $o{ 'recent dir' }: $!";

  my $dir = get_dir();

  for my $f ( @{ $dir } )
  {
    my $cam = $f->{ 'cam' };

    next if ! exists $out_templates{ $cam };

    if ( ! exists $old_recs{ $cam } ) # so this one is live recording
    {
      $old_recs{ $cam } = [];

      $debug and print ". [$$] Cam <$cam> LIVE index is ", $f->{ 'index' }, "\n";
    }

    next if ( $f->{ 'mtime' } < $event_start - $snap_time ); # out of snap seq. get to the next cam then

    push @{ $old_recs{ $cam } }, $f;
  } # for my $f ( @{ $dir } )

  ####################################################
  # now linking what's found into the event dir
  ####################################################

  my $time_left = $snap_time; # seconds. dumb logic here

  for my $cam ( @cams_capture )
  {
    next if ! exists $old_recs{ $cam };

    my $sec = 0;

    my $old_recs_count = $#{ $old_recs{ $cam } };
    $out_index{ $cam } = $old_recs_count + 2;

    for my $i ( 0..$old_recs_count )
    {
      my $orig_file = $old_recs{ $cam }->[$i]->{'name'};
      my $outname = $out_templates{ $cam };

      my $index = sprintf '%03d(%d sec)', $old_recs_count - $i + 1, $sec;
      $outname =~ s/%index%/$index/g;

      $debug and print "+ [$$] cam: <$cam> OLD seg link '$orig_file'\n";# --> '$outname'\n";

      link $orig_file, $outname or print "! link $orig_file, $outname: $!\n";

      $sec -= $old_recs{ $cam }->[$i]->{'seglen'};
    }

    request_sync();

    $debug and print "+ [$$] Now waiting ", (defined($persistent) ? 'PERSISTENTLY' : "for next $snap_time seconds" ), " for cam $cam, past the ", $old_recs{ $cam }->[0]->{ 'name' }, "\n";
  }

  ####################################################
  # now wait for next segment(s) to appear
  # for each cam and link it too
  ####################################################

  while( 1 )
  {
    sleep( 5 );

    if ( defined( $persistent ) )
    {
      if ( ! -f $persistent_flag ) # we're done
      {
        $debug and print "- [$$] Persistency flag gone - ending\n";
        last;
      }
    }

    else # 'once' snap mode
    {
      --$time_left;

      $debug and print ( $time_left % 10 == 0 ? "\n$time_left sec" : '.' );

      $time_left <= 0 and last;

      last if ! keys %out_index; # once mode - snap time exceeded for all cameras
    }

    $dir = get_dir(); # get fresh list

    for my $cam ( keys %out_index )
    {
      for my $f ( @{ $dir } )
      {
        next if ! defined( $f ); # already processed file
        next if $f->{ 'cam' } ne $cam;

        last if $f->{ 'mtime' } < $event_start; # low end of snap seq. get to the next cam then
        last if $f->{ 'name' } eq $old_recs{ $cam }->[0]->{ 'name' }; # no new files yet

        # end of snap time for this cam?
        if ( ! defined( $persistent ) and $f->{ 'mtime' } > $event_start + $snap_time )
        {
          delete $out_index{ $cam };
          last;
        }

        my $outname = $out_templates{ $cam };
        my $index = sprintf '%03d(%d sec)', $out_index{ $cam }, ($out_index{ $cam } - $#{ $old_recs{ $cam } } - 1) * $f->{ 'seglen' };
        $outname =~ s/%index%/$index/g;

        $debug and print "+ [$$] cam <$cam> LIVE seg link '", $f->{'name'}, "\n";#"' --> '$outname'\n";

        link $f->{ 'name' }, $outname or print "! link ", $f->{'name'}, " $outname: $!\n";

        $debug or request_sync();

        ++$out_index{ $cam };

        $old_recs{ $cam }->[0]->{'name'} = $f->{'name'}; # let's watch past this one

        $f = undef;

        last;
      } # @dir
    } # cams
  } # while time left or persistent

  $debug and print "--- [$$] main() done\n";
}
####################################################
# end of main.
####################################################

####################################################
# returns current recordings directory contents
sub get_dir
{
  my $list = [];

#  my $cmd = "/bin/sh -c \"/bin/ls -ltQ --time-style=+\%s *" . $o{ 'records ext' } . "\" |";
  my $cmd = "/bin/ls -ltQ --time-style=+\%s";

  open LS, '-|', $cmd or die "$cmd: $!";

  while(<LS>)
  {
    s/[\r\n]+$//;

    #$debug and print "+ Recording: $_\n";

    # See cam_common.conf for template description
    my $re = '^(\S+\s+){4}(?<size>\d+)\s+(?<mtime>\d+)\s+"' . $o{ 'records list re' } . '"$';

    /$re/ or next;

    push @{ $list }, { %+ };
  }

  close LS;
  return $list;
}

#############################################################
sub request_sync
{
  if ( $debug )
  {
    print ". [$$] Request sync\n";
    return;
  }

  touch_file( $o{ 'sync flag' } );
}

#############################################################
sub touch_file
{
  my $file = shift @_;

  if( ! open F, '>', $file )
  {
    print STDERR "Can't touch $file: $!\n";
    return 0;
  }

  for my $line ( @_ )
  {
    print F $line;
  }

  close F;

  $debug and print "* touched $file\n";
  return 1;
}

#############################################################
#############################################################
#############################################################
# in: none, out: none
sub mqtt_run
{
  #$mqtt = Net::MQTT::Simple::SSL->new( $o{ 'mqtt server' },
  #  {
  #    SSL_ca_path   => $o{ 'mqtt ssl ca' },
  #    SSL_cert_file => $o{ 'mqtt ssl crt' },
  #    SSL_key_file  => $o{ 'mqtt ssl key' },
  #  } );
  $mqtt = Net::MQTT::Simple->new( $o{ 'mqtt server' } );

  $mqtt or die 'MQTT to ' . $o{ 'mqtt server' } . ' failed: ' . $@;

  #$mqtt->publish( "topic/here" => "Message here" );
  #$mqtt->retain( "topic/here" => "Message here" );

  $debug and print "+ MQTT: run()\n";

  $mqtt->run(
      $o{ 'mqtt topic' } => \&mqtt_got_message,
      '#' => \&mqtt_misc
  );

  exit(1);
}

#############################################################
# misc messages: process timeouts, etc
# in: topic, message - ignored
sub mqtt_misc
{
  #my ( $topic, $message ) = @_;

  $debug and print "--- MQTT(#): msg on topic: ", $_[ 0 ], "\n";

  my $t = time;

  for my $e ( keys %mqtt_pers_timeouts )
  {
    next if ( $mqtt_pers_timeouts{ $e }->{ 't/o' } < $t );

    $debug and print "? MQTT: timeout of persistency: ", $mqtt_pers_timeouts{ $e }->{ 'msg' }, "\n";

    mqtt_got_message( '<timeout>', $mqtt_pers_timeouts{ $e }->{ 'msg' } ); # stop it
  }
}

#############################################################
# one-time save.
# in: topic, message
# message is <event id>,<once>|<persistent on/off>,<cam1>[,<cam2>...]
sub mqtt_got_message
{
  my ( $topic, $message ) = @_;
  $debug and print "+ mqtt_get_message(): topic: '$topic', msg: '$message'\n";

  $message =~ s/[\`\'\"\&\\\|><;]+/_/g; # security
  my ( $event, $mode, @cam_list ) = split ',', $message;
  $mode = lc $mode;
  $mode =~ s/^persistent //;

  if ( $mode eq 'once' )
  {
  } # once

  elsif ( $mode eq 'on' )
  {
    # update timer if same event arrived
    if ( ! exists( $mqtt_pers_timeouts{ $event } ) )
    {
      $mqtt_pers_timeouts{ $event } = {};
    }

    $mqtt_pers_timeouts{ $event }->{ 't/o' } = time + $o{ 'mqtt persistent timeout' };
    $mqtt_pers_timeouts{ $event }->{ 'msg' } = join( ',', ( $event, 'off', @cam_list ) );
  } # pers on

  elsif( $mode eq 'off' )
  {
    exists( $mqtt_pers_timeouts{ $event } ) and delete( $mqtt_pers_timeouts{ $event } );
  }

  else #might stop all here
  {
    return;
  }

  #$debug and return;

  return if 0 < fork();

  init();

  @cams_capture = @cam_list;
  $event_id = $event;
  $mode ne 'once' and $persistent = $mode;

  exit( main() );
}

#############################################################
sub help
{
  print q~Use: cam-event.pl [options] [camera ids to snap from]
  Options:
    -c <config_path>
    -d - debug
    -e <event name or id>
    -h - this help
    -l - log on
    -m - MQTT monitor mode
    -p <on/off> - persistent recording start/stop
    -s <snap_time> - request non-default snaps to sync. default is ~, $o{ 'default snap time' }, q~
Known camera IDs: ~, join(', ', keys %cams), "\n";

  exit(0);
}

#############################################################
# initialize for a new run
sub init
{
  @cams_capture = keys %cams;
  $event_start = time; # base for snap counts
  $log = 0; # no log will be produced
  $mqtt = undef;

  $persistent = undef;

  if ( ! defined( $snap_time ) || $snap_time < 5 || $snap_time > 3600 )
  {
    $snap_time = $o{ 'default snap time' };
  }

  defined( $event_id ) or $event_id = 'test_event';
}

#############################################################
sub load_config
{
  my $file = $_[0];

  if ( ! -r $file )
  {
    $file =~ m?/? and croak "Can't open config: $file";

    $file = dirname(__FILE__) . '/' . $file;

    -r $file or $file = '/etc/smarthome/cams/' . $_[0];
  }

  $debug and print "+ Loading config: $file\n";

  my $cfg;
  open C, '<', $file or die "config file: '$file': $!";
  sysread( C, $cfg, 999999 ) or die "config is empty?";
  close C;
  eval $cfg;
}
