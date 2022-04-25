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

package LXRng::Repo::GitRaw::Directory;

use strict;
use Git::Raw;

use base qw(LXRng::Repo::Directory);

sub new {
    my ($class, $name, $obj, $commit) = @_;

    $name =~ s,/*$,/,;
    return bless({name => $name, obj => $obj, commit => $commit},
		 $class);
}

sub cache_key {
    my ($self) = @_;

    return $$self{'obj'}->owner()->path().":".$$self{'obj'}->id();
}

sub time {
    my ($self) = @_;
    return 0;
}

sub size {
    my ($self) = @_;
    return '';
}

sub contents {
    my ($self) = @_;

    my $prefix = $$self{'name'};
    $prefix =~ s,^/+,,;
    my (@dirs, @files);
    foreach my $e ($$self{'obj'}->entries()) {
	if ($e->type() eq Git::Raw::Object::TREE()) {
	    push(@dirs, LXRng::Repo::GitRaw::Directory->new($prefix.$e->name(),
							    $e->object(),
							    $$self{'commit'}));
	}
	elsif ($e->type() eq Git::Raw::Object::BLOB()) {
	    push(@files, LXRng::Repo::GitRaw::File->new($prefix.$e->name(),
							$e->object(),
							$$self{'commit'}));
	}
    }

    return (@dirs, @files);
}

1;
