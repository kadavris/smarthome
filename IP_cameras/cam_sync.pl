#!/bin/perl
# this script/service should be run under user who owns cloud credentials
use strict;
use warnings;
use File::Basename;
use Carp;

my $debug;
my %o;

load_config( 'cam_sync.config' ); # get paths at least

my $persistent_flag = sprintf ( $o{ 'persistent flag template' }, '*' );

while(1)
{
  sleep(1);

  if ( -f $o{ 'sync flag' } ) # one-time event. removing flag so sync may be restarted soon
  {
    unlink $o{ 'sync flag' } and print STDERR "Can't unlink ", $o{ 'sync flag' }, ": $!\n";
  }

  elsif ( ! glob( $persistent_flag ) ) # persistent backup?
  {
    next;
  }

  my $cmd = "/bin/rclone -q --exclude '*.log' copy \"" . $o{ 'events dir' } . '" "' . $o{ 'cloud id' } . ':' . $o{ 'cloud path' } . '/"';

  system $cmd;
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
