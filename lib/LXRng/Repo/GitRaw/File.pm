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

package LXRng::Repo::GitRaw::File;

use strict;

use base qw(LXRng::Repo::File);
use LXRng::Repo::TmpFile;
use File::Temp qw(tempdir);

sub new {
    my ($class, $name, $obj, $commit) = @_;

    return bless({name => $name, obj => $obj, commit => $commit},
		 $class);
}

sub time {
    my ($self) = @_;

    # This is may be too slow. See LXRng::Repo::Git::File.
    my $cur = $$self{'commit'};
    while ($cur) {
	my ($parent) = $cur->parents();
	last unless $parent;
	my $prevobj = $parent->tree()->entry_bypath($$self{'name'});
	last unless $prevobj;
	last if $prevobj->id() ne $$self{'obj'}->id();
	$cur = $parent;
    }
    return $cur->time();
}

sub size {
    my ($self) = @_;
    return $$self{'obj'}->size();
}

sub handle {
    my ($self) = @_;

    my $content = $$self{'obj'}->content();
    open(my $fh, "<", \$content);
    return $fh;
}

sub revision {
    my ($self) = @_;

    return $$self{'obj'}->id();
}

sub phys_path {
    my ($self) = @_;

    return $$self{'phys_path'} if exists $$self{'phys_path'};

    my $tmpdir = tempdir() or die($!);
    open(my $phys, ">", $tmpdir.'/'.$self->node) or die($!);
    print($phys $$self{'obj'}->content()) or die($!);
    close($phys) or die($!);

    return $$self{'phys_path'} =
	LXRng::Repo::TmpFile->new(dir => $tmpdir,
				  node => $self->node);
}

1;
