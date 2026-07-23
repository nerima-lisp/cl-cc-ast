#!/usr/bin/env perl

use strict;
use warnings;
use POSIX qw(:sys_wait_h);

my ($timeout, @command) = @ARGV;
die "usage: $0 TIMEOUT COMMAND [ARG ...]\n"
  unless defined $timeout && @command;
die "TIMEOUT must be a positive integer\n"
  unless $timeout =~ /\A[1-9][0-9]*\z/;

my $child = fork;
die "fork failed: $!\n" unless defined $child;

if ($child == 0) {
  setpgrp(0, 0) or die "setpgrp failed: $!\n";
  exec @command or do {
    warn "exec failed for $command[0]: $!\n";
    exit 127;
  };
}

# Move the child into its own process group from the parent as well. This is
# best-effort because the child may have already reached exec after its own
# setpgrp call.
setpgrp($child, $child);

my $timed_out = 0;

local $SIG{ALRM} = sub {
  $timed_out = 1;
  warn "timed out after $timeout seconds\n";
  kill 'TERM', -$child;
  # The direct child signal covers a timeout racing before setpgrp completes.
  kill 'TERM', $child;
  sleep 1;
  kill 'KILL', -$child;
  kill 'KILL', $child;
};

alarm $timeout;
my $waited = waitpid $child, 0;
alarm 0;

exit 124 if $timed_out;
die "waitpid failed\n" if $waited < 0;

if (WIFEXITED($?)) {
  exit WEXITSTATUS($?);
}

if (WIFSIGNALED($?)) {
  my $signal = WTERMSIG($?);
  die "command terminated by signal $signal\n";
}

die "command terminated abnormally\n";
