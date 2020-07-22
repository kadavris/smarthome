#!/bin/perl
# this is the part of surveillance scripts
# This particular is a single-cam service handler.
use warnings;
use strict;
use Getopt::Long;
use File::Path qw(make_path);
use File::Basename;
use Carp;

#these are from config file:
my %cams;
my %o; # options

# local vars:
my $segment_time; # how long a piece of record to be
my $debug = 0; # screen output is not suppressed
my $log = 0; # no log will be produced
my $config_path = 'cam_service.config'; # default
my $show_help = 0;

####################################################

GetOptions (
  'c=s' => \$config_path,
  'd' => \$debug,
  'h' => \$show_help,
  'l' => \$log,
  't=i' => \$segment_time,
) or die "GetOptions: $!";

umask 0007;

load_config( $config_path );

defined( $segment_time ) or $segment_time = $o{ 'default segment time' };

if ( $#ARGV < 0 || $show_help ) # must be camera id after options
{
  help(0);
}

my $cam_id = $ARGV[0];

exists $cams{ $cam_id } or report( 1, "!ERROR! invalid camID: $cam_id" );

if ( ! -d $o{ 'recent dir' } && ! make_path( $o{ 'recent dir' } ) )
{
  report( 1, 'Problem with recordings path: '. $o{ 'recent dir' } . '.' );
}

my $logfile;

if ( $log )
{
  my $timestamp = get_times( 'dt' ); # this will be used for the log too
  $logfile = $o{ 'records log template' };
  $logfile =~ s/%dt%/$timestamp/g;
  $logfile =~ s/%cam%/$cam_id/g;
  $logfile =~ s/%pid%/$$/g;
  $logfile = $o{ 'recent dir' } . '/' . $logfile;
}

my $nag_time = 0; # time to show the next nag if any
my $elapsed = 0;
my $error_text = '';
my $consequtive_errors = 0; # bail out if too many in a row
my @log_buffer; # will hold ffmpeg's output for error analysis

while( 1 )
{
  $error_text = check_space( $o{ 'recent dir' }, $o{ 'limit total size' } );

  next if $error_text ne '';

  my $out_file = $o{ 'records name template' };
  $out_file =~ s/%dt%/%Y.%m.%d,%H.%M.%S/g;
  $out_file =~ s/%cam%/$cam_id/g;
  $out_file =~ s/%pid%/$$/g;
  $out_file =~ s/%seglen%/$segment_time/g;
  $out_file =~ s/%index%/$o{'records index tpl'}/g; # should be last because of printf code

  my $cmd = '/bin/ffmpeg -loglevel level+warning -f "' . $cams{ $cam_id }->{ 'proto' } . '" -rtsp_transport tcp'
          . ' -i "' . ( exists( $cams{ $cam_id }->{ 'proxy port' } ) ? $cams{ $cam_id }->{ 'record from' } : $cams{ $cam_id }->{ 'source' } ) .'"'
          . ' -y -c copy -f segment -segment_time ' . $segment_time . ' -reset_timestamps 1 -strftime 1'
          . ' "' . $o{ 'recent dir' } . "/$out_file\" 2>&1";

  @log_buffer = ();

  if ( $debug )
  {
    print ' ! DEBUG cmd >>> ', $cmd, "\n";
    exit(0);
  }

  print 'Starting: ', $cmd, "\n";

  $elapsed = time;

  my $ffh; # ffmpeg output handle

  if( ! open $ffh, '-|', $cmd )
  {
    $error_text = " ! open($cmd): $!\n";
    next;
  }

  save_status( 0, 'OK' ); # re-set initial state

  while( <$ffh> )
  {
    do_log( $_ );

    if ( /^\[error\].+: Connection refused/ )
    {
      if ( exists ( $cams{ $cam_id }->{ 'proxy port' } ) && defined( $cams{ $cam_id }->{ 'proxy port' } ) )
      {
        do_log( $error_text = " + trying to restart proxy\n" );

        system '/bin/systemctl restart cam_proxy@' . $cam_id;
      }
      else
      {
        report( 0, $error_text = " ! FATAL ERROR ! camera is not proxied and ffmpeg can't connect. Zombifying." );
      }

      last;
    } # if ( /^\[error\].+: Connection refused/ )
  } # while( <$ffh> )

  close $ffh;

  if ( time - $elapsed < $segment_time )
  {
    $error_text = 'ffmpeg exitted too fast.' . $error_text;
    do_log( $error_text );
  }
}
continue
{
  if ( $error_text ne '' )
  {
    save_status( 1, $error_text );

    if ( time > $nag_time ) # time to log it
    {
      report( 0, $error_text, "\nWaiting $segment_time seconds before restarting ffmpeg" );

      $nag_time = time + 3600;

      sleep( $segment_time );
    }

    ++$consequtive_errors;
  }
  else
  {
    save_status( 0, 'OK' );
    $consequtive_errors = 0;
  }

  if ( $consequtive_errors > 10 )
  {
    print STDERR "Too many consequtive errors - exitting. The last one is: $error_text\n";
    save_status( 2, $error_text );
    exit(1);
  }

  $error_text = '';

  flush_log();

  sleep( 15 );
} # while(1)

exit(0);

#####################################
# in: dir, min size in _bytes_
# out: empty string if OK or error description
sub check_space
{
  my $cmd = '/usr/bin/df -k "' . $_[0] . '" |'; # NOTE: Kb!

  open FSP, $cmd or next;
  $_ = <FSP>; # header
  $_ = <FSP>; # data
  close FSP;
  /^(\S+\s+){3}(\d+)/;

  my $free = int( $2 ) * 1024;

  $free >= $_[1] and return ''; # OK to go.

  $debug and print STDERR "check_space(): low space in $_[0]: $free vs $_[1] bytes!\n";

  return ' Free space in ' . $_[0] . ' is low (' . $free . ' bytes).';
}

#############################################################
sub do_log
{
  my $dt = get_times( 'dt' );

  foreach ( @_ )
  {
    my $in = $_;

    $in =~ s/\n+$//;

    my @l = split /\n/, $in;

    for my $s ( @l )
    {
      push @log_buffer, $dt . ' ' . $s;
    }
  }
}

#############################################################
sub flush_log
{
  return if ! @log_buffer;

  if ( $debug )
  {
    foreach( @log_buffer )
    {
      print STDERR $_, "\n";
    }

    @log_buffer = ();

    return;
  }

  return if ! $log;

  if ( open( my $logh, '>>', $logfile) )
  {
    foreach( @log_buffer )
    {
      print $logh $_, "\n";
    }

    close $logh;

    @log_buffer = ();
  }
  else
  {
    print STDERR "! open $logfile: $!\n";
  }
}

#############################################################
# in: code, messsage
sub save_status
{
  return if ! defined( $o{ 'state file tpl' } );
  
  my $file = $o{ 'state file tpl' };
  $file =~ s/%cam%/$cam_id/g;

  if ( open( my $st, '>', $file ) )
  {
    print $st $_[1], "\n";
    print $st $_[0], "\n";
    close $st;
  }
}

#############################################################
# in: bool - true to exit
# will not send email until exit is wanted.
sub report
{
  my $do_exit = defined( $_[0] ) ? shift : 0;

  $debug and print join "\n", @_;

  return if ! $do_exit;

  open M, '|-', '/sbin/sendmail ' . $o{ 'whine email' } or croak "sendmail: $!/$?";
  print M "From: cam_service for '$cam_id'\n";
  print M "To: " . $o{ 'whine email' } . "\n";
  print M "\n\n" . join("\n", @_), "\n\n";

  if ( @log_buffer )
  {
    print M "\nLog follows:\n";

    foreach ( @log_buffer )
    {
      print M $_;
    }
  }

  close M;

  flush_log();

  exit($? > $! ? $? : $!);
}

#####################################
sub help
{
  print "Use: cam_service.pl [options] <camera id to record from>\n";
  print "Options:\n\t-c <config file path>\n\t-d - debug\n\t-l - make log\n\t-t <seconds> - segment_time (see default value in the config)\n\t";
  print "Known camera IDs: ", join(', ', keys %cams), "\n";
  exit(1);
}

#############################################################
sub load_config
{
  my $file = $_[0];

  if ( ! -r $file )
  {
    $file =~ m?/? and print "Can't open config: $file" and help();

    $file = dirname(__FILE__) . '/' . $_[0];

    -r $file or $file = '/etc/smarthome/cams/' . $_[0];
  }

  $debug and print "+ Loading config: $file\n";

  my $cfg;
  open C, '<', $file or die "config file: '$file': $!";
  sysread( C, $cfg, 999999 ) or die "config is empty?";
  close C;
  eval $cfg;
}
