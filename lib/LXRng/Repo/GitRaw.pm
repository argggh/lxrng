# Copyright (C) 2022 Arne Georg Gleditsch <lxr@linux.no>.
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

package LXRng::Repo::GitRaw;

use strict;
use Git::Raw;
use LXRng::Cached;
use LXRng::Repo::GitRaw::Iterator;
use LXRng::Repo::GitRaw::File;
use LXRng::Repo::GitRaw::Directory;

sub new {
    my ($class, $root, %args) = @_;

    my $repo = Git::Raw::Repository->open($root);

    return bless({root => $root, repo => $repo, %args}, $class);
}

sub cache_key {
    my ($self) = @_;

    return $$self{'root'};
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

sub _all_tags {
    my ($self) = @_;

    cached {
	my @tags = $$self{'repo'}->tags();
	my %tags = map { $_->name() => $_->target()->id() } @tags;
	return %tags;
    };
}

sub allversions {
    my ($self) = @_;

    my %tags = $self->_all_tags();
    my @tags;
    foreach my $n (keys %tags) {
	next if $$self{'release_re'} and $n !~ $$self{'release_re'};
	push(@tags, $n);
    }
    return (sort {_sort_key($b) cmp _sort_key($a) } @tags);
}

sub node {
    my ($self, $path, $release, $rev) = @_;

    $path =~ s,^/+,,;
    $path =~ s,/+$,,;

    my %tags = $self->_all_tags();
    my $ref = $tags{$release};
    return undef unless $ref;
    my $commit = $$self{'repo'}->lookup($ref);
    my $tree = $commit->tree();
    my $type;
    my $obj;
    if ($path eq '') {
	$type = Git::Raw::Object::TREE();
	$obj = $tree;
    }
    elsif ($rev) {
	$type = Git::Raw::Object::BLOB();
	$obj = $$self{'repo'}->lookup($rev);
    }
    else {
	my $node = $tree->entry_bypath($path);
	return undef unless $node;
	$type = $node->type();
	$obj = $node->object();
    }

    if ($type eq Git::Raw::Object::TREE()) {
	return LXRng::Repo::GitRaw::Directory->new($path, $obj, $commit);
    }
    elsif ($type eq Git::Raw::Object::BLOB()) {
	return LXRng::Repo::GitRaw::File->new($path, $obj, $commit);
    }
    else {
	return undef;
    }
}

sub iterator {
    my ($self, $release) = @_;

    my %tags = $self->_all_tags();
    my $ref = $tags{$release};
    my $commit = $$self{'repo'}->lookup($ref);

    return LXRng::Repo::GitRaw::Iterator->new($commit);
}

1;
