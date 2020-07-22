#!/bin/perl
# this is the part of surveillance scripts
# This particular is a camera proxy handler.
use warnings;
use strict;
use Getopt::Long;
use Carp;

#these are from config file:
my %cams;
my %o; # options

# local vars:
my $debug;
my $log;
my $logfile;
my $config_path = 'cam_proxy.config'; # default
my $show_help = 0;

####################################################

GetOptions (
  'c=s' => \$config_path,
  'd' => \$debug,
  'h' => \$show_help,
  'l=i' => \$log,
) or die "GetOptions: $!";

load_config( $config_path );

if ( $#ARGV < 0 || $show_help ) # must be camera id after options
{
  help(0);
}

my $cam_id = $ARGV[0];

exists $cams{ $cam_id } or report_and_exit( "!ERROR! invalid camID: $cam_id" );

$cams{ $cam_id }->{ 'proto' } ne 'rtsp' and report_and_exit( "!ERROR! camera: $cam_id is not rtsp" );

if ( ! exists( $cams{ $cam_id }->{ 'proxy port' } ) || ! defined( $cams{ $cam_id }->{ 'proxy port' } ) )
{
  report_and_exit( "!ERROR! camera: $cam_id bad port" );
}

#live555ProxyServer [-v|-V] [-t|-T <http-port>] [-p <rtspServer-port>] [-u <username> <password>] [-R] [-U <username-for-REGISTER> <password-for-REGISTER>] <rtsp-url-1> ... <rtsp-url-n>

my $cmd = '/bin/live555ProxyServer -t -p ' . $cams{ $cam_id }->{ 'proxy port' };

if ( $log == 1 )
{
   $cmd .= ' -v';
}
elsif ( $log > 1 )
{
   $cmd .= ' -V';
}

$cmd .= " '" . $cams{ $cam_id }->{ 'source' } . "'";

$log > 0 and $cmd .= " > '" . $o{ 'records base dir' } . '/cam_proxy_' . $cam_id . '-' . get_times( 'dt' ) . '.log\' 2>&1';

print 'Starting: ', $cmd, "\n";

$debug and exit(0);

system $cmd;

exit($!);

#####################################
sub help
{
  print "Use: cam_proxy.pl [options] <camera id>\n";
  print "Options:\n\t-c <config file path>\n\t-d - debug\n\t-l - log verbosity level\n\t";
  print "Known camera IDs: ", join(', ', keys %cams), "\n";
  exit(1);
}

#############################################################
sub report_and_exit
{
  if ( $debug )
  {
    print join "\n", @_;
  }
  else
  {
    open M, '|-', '/sbin/sendmail ' . $o{ 'whine email' } or croak "sendmail: $!/$?";
    print M "From: cam_proxy for '$cam_id'\n";
    print M "To: " . $o{ 'whine email' } . "\n";
    print M "\n\n" . join("\n", @_);

    if ( open( L, '<', $log) )
    {
      print M "\nLog file follows:\n";

      while(<L>)
      {
        print M $_;
      }

      close L;
    }

    close M;

    if ( $log )
    {
      open L, '>>', $logfile or croak "$logfile: $!";
      print L join("\n", @_);
      close L;
    }
  }

  exit($? > $! ? $? : $!);
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

  #unless ($return = do $file)
  #{
  #  croak "couldn't parse $file: $@" if $@;
  #  croak "couldn't do $file: $!"    unless defined $return;
  #  croak "couldn't run $file"       unless $return;
  #}

  my $cfg;
  open C, '<', $file or die "config file: '$file': $!";
  sysread( C, $cfg, 999999 ) or die "config is empty?";
  close C;
  eval $cfg;

  defined( $debug ) or $debug = 0;
  defined( $log ) or $log = 0;
}
