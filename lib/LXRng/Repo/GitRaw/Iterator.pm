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

package LXRng::Repo::GitRaw::Iterator;

use strict;
use Git::Raw::Object;
use LXRng::Repo::GitRaw::File;

sub _collect_files {
    my ($refs, $tree, $prefix) = @_;
    foreach my $e ($tree->entries()) {
	if ($e->type == Git::Raw::Object::BLOB()) {
	    push(@$refs, [$prefix.$e->name(), $e->object()]);
	} elsif ($e->type == Git::Raw::Object::TREE()) {
	    _collect_files($refs, $e->object(), $prefix.$e->name()."/");
	}
    }
}

sub new {
    my ($class, $commit) = @_;
    my $root = $commit->tree();
    my @refs;
    _collect_files(\@refs, $root, "");

    return bless({refs => \@refs, commit => $commit}, $class);
}

sub next {
    my ($self) = @_;

    return undef unless @{$$self{'refs'}} > 0;
    my $file = shift(@{$$self{'refs'}});

    return LXRng::Repo::GitRaw::File->new($$file[0], $$file[1], $$self{'commit'});
}

1;
