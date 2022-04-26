# Copyright (C) 2008 Arne Georg Gleditsch <lxr@linux.no>.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# The full GNU General Public License is included in this distribution
# in the file called COPYING.

package LXRng::Repo::Git;

use strict;
use Memoize;
use LXRng::Cached;
use LXRng::Repo::Git::Iterator;
use LXRng::Repo::Git::File;
use LXRng::Repo::Git::Directory;

use vars qw($has_gitraw);

BEGIN {
    eval { require LXRng::Repo::GitRaw; };
    if ($@ eq '') {
	$has_gitraw = 1;
    }
}

sub _git_cmd {
    my ($self, $cmd, @args) = @_;

    my $git;
    my $pid = open($git, "-|");
    die $! unless defined $pid;
    # warn("git --git-dir=".$$self{'root'}." $cmd @args");
    
    if ($pid == 0) {
	exec('git', '--git-dir='.$$self{'root'}, $cmd, @args);
	warn $!;
	kill(9, $$);
    }
    return $git;
}

sub new {
    my ($class, $root, %args) = @_;

    if ($has_gitraw) {
	return LXRng::Repo::GitRaw->new($root, %args);
    }

    memoize('_release_timestamp');

    return bless({root => $root, %args}, $class);
}

sub cache_key {
    my ($self) = @_;

    return $$self{'root'};
}

sub _release_timestamp {
    my ($self, $release) = @_;

    my $cinfo = $self->_git_cmd('cat-file', '-t', $release);
    my ($type) = <$cinfo> =~ /(\S+)/;

    return undef unless $type eq 'tag' or $type eq 'commit';

    my $cinfo = $self->_git_cmd('cat-file', $type, $release);

    my $time;
    while (<$cinfo>) {
	$time = $1 if /^author .*? (\d+(?: [-+]\d+|))$/ ;
	$time ||= $1 if /^committer .*? (\d+(?: [-+]\d+|))$/ ;
	$time ||= $1 if /^tagger .*? (\d+(?: [-+]\d+|))$/ ;
    }

    return $time || 0;
}

sub _use_author_timestamp {
    my ($self) = @_;

    return $$self{'author_timestamp'};
}

sub _sort_key {
    my ($v) = @_;

    $v =~ s/(\d+)/sprintf("%05d", $1)/ge;
    return $v;
}

sub allversions {
    my ($self) = @_;

    cached {
	my @tags;
	my $tags = $self->_git_cmd('tag', '-l');
	while (<$tags>) {
	    chomp;
	    next if $$self{'release_re'} and $_ !~ $$self{'release_re'};
	    push(@tags, $_);
	}

	return (sort {_sort_key($b) cmp _sort_key($a) } @tags);
    };
}

sub node {
    my ($self, $path, $release, $rev) = @_;

    $path =~ s,^/+,,;
    $path =~ s,/+$,,;

    if ($path eq '') {
	my $git = $self->_git_cmd('rev-list', '--max-count=1', $release);
	my $ref = <$git>;
	return undef unless $git =~ /\S/;
	close($git);
	chomp($ref);
	return LXRng::Repo::Git::Directory->new($self, '', $ref);
    }

    my $type;
    if ($rev) {
	$type = 'blob';
    }
    else {
	my $git = $self->_git_cmd('ls-tree', $release, $path);
	my ($mode, $gitpath);
	($mode, $type, $rev, $gitpath) = split(" ", <$git>, 4);
    }

    if ($type eq 'tree') {
	return LXRng::Repo::Git::Directory->new($self, $path, $rev, $release);
    }
    elsif ($type eq 'blob') {
	return LXRng::Repo::Git::File->new($self, $path, $rev, $release);
    }
    else {
	return undef;
    }
}

sub iterator {
    my ($self, $release) = @_;

    return LXRng::Repo::Git::Iterator->new($self, $release);
}

1;
