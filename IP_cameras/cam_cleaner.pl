#!/bin/perl
# This is the script for cleaning up old camera recordings
use Carp qw(carp croak shortmess);
use File::Basename;
use strict;
use warnings;
use Getopt::Long;

my %o; # options

my $config_file = 'cam_cleaner.config'; # default
my $debug = 0; # screen output is not suppressed
my $log = 0; # no log will be produced
my $show_help = 0;

GetOptions(
  'c=s' => \$config_file,
  'd' => \$debug,
  'h' => \$show_help,
  'l' => \$log,
) or die("getoptions: $@");

load_config( $config_file );

$show_help and help();

my @files;
my @sizes;
my @cams;
my @age;
my $total_size = 0;

if ( ! -d $o{ 'recent dir' } )
{
  if ( $log || $debug )
  {
    print 'No ' . $o{ 'recent dir' } . " directory. Exitting peacefully\n";
  }
  exit(1);
}

chdir $o{ 'recent dir' } or croak 'chdir ' . $o{ 'recent dir' } . ": $!";

my $cmd = qq~/bin/sh -c "/bin/ls -ltQ --time-style=+\%s" |~;

open LS, $cmd or die "ls: $!";
while(<LS>)
{
  s/[\r\n]+//;

  #-rw-rw---- 1 smarthome smarthome 1280925 1532515397 "xiao-2018.07.23,18.53.01-5456-000010280-15.mp4"
  /^(\S+\s+){4}(?<s>\d+)\s+(?<ts>\d+)\s+\"(?<file>(?<cam>\w+)-.+)\"$/ or next;
  push @sizes, $+{'s'};
  push @files, $+{'file'};
  push @cams, $+{'cam'};
  push @age, $+{'ts'};
  $total_size += $+{'s'};
}
close LS;

if ( $debug )
{
  printf "Total files %d of %ld bytes\n", $#files + 1, $total_size;
}

my $saved_size = 0;

while ( $#files > -1 && $total_size > $o{ 'limit total size' } )
{
  if ( $debug )
  {
    print "Marking for removal $files[$#files] of $sizes[$#sizes] bytes\n";
  }
  else
  {
    if ( $files[$#files] =~ /log$/i ) # checking if log is old enough to get cleaned
    {
      if ( $age[$#age] + 3600 * 24 < time ) # log remain for a 24h
      {
        unlink $files[$#files] or print "unlink $files[$#files]: $!\n";
      }
    }
    else
    {
      unlink $files[$#files] or print "unlink $files[$#files]: $!\n";
    }
  }

  $saved_size += $sizes[$#sizes];
  $total_size -= pop @sizes;
  pop @cams;
  pop @files;
  pop @age;
}

$debug and print 'Saved ', $saved_size/1024, " K bytes\n";

exit(0);

#############################################################
sub help
{
  print "Use: cam_cleaner.pl -c config_file\n\t-d - debug mode (no deletions, just braggin)\n\t-l - log on\n";
  exit(1);
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
