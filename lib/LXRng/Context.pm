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

package LXRng::Context;

use strict;
use LXRng;

use vars qw($cached_config $cached_config_stat $cached_config_age);

sub new {
    my ($self, %args) = @_;

    $self = bless({}, $self);

    my $config = $self->read_config();

    if ($args{'query'}) {
	# Argle.  Both CGI and CGI::Simple seem to botch this up, in
	# different ways.  CGI breaks if SCRIPT_NAME contains regex
	# metachars, and CGI::Simple does funny things if SCRIPT_NAME
	# is the empty string.  Do it by hand...
	my $host = $ENV{'REQUEST_SCHEME'}.'://'.
	    ($ENV{'HTTP_HOST'} || $ENV{'SERVER_NAME'}).
	    ($ENV{'SERVER_PORT'} == ($ENV{'REQUEST_SCHEME'} eq 'https' ? 443 : 80)
	     ? '' : ':'.$ENV{'SERVER_PORT'});
	my $path = $ENV{'REQUEST_URI'};
	$path =~ s/\?.*//;
	$path =~ s,/+,/,g;
	$path =~ s/%([0-9a-f][0-9a-f])/hex($1) >= 32 ? pack("C", hex($1)) : '_'/ge;
	$$self{'req_base'} = $host.$ENV{'SCRIPT_NAME'};

	foreach my $p ($args{'query'}->param) {
	    my @val = $args{'query'}->param($p);
	    for (@val) {
		utf8::upgrade($_);
	    }
	    $$self{'params'}{$p} = [@val];
	}
	my @prefs = $args{'query'}->cookie('lxr_prefs');
	if (@prefs) {
	    $$self{'prefs'} = { 
		map { /^(.*?)(?:=(.*)|)$/; ($1 => $2) } @prefs };
	}
	else {
	    if ($args{'query'}->user_agent() =~ /(Gecko|Opera)\//) {
		$$self{'prefs'}{'navmethod'} = 'ajax';
	    }
	}
	foreach my $tree (keys %$config) {
	    my $base = $$config{$tree}{'base_url'};
	    $base =~ s,^https?://[^/]+,,;
	    $base =~ s,/*$,/,;

	    if ($path =~ m,^\Q$base\E(\Q$tree\E|)([+][^/]+|)(?:$|/)(.*),) {
		@$self{'tree', 'path'} = ($1.$2, $3);
		last;
	    }
	}
	unless ($$self{'tree'}) {
	    if ($ENV{'PATH_INFO'} =~ m,^/?([^/]+)/?(.*),) {
		@$self{'tree', 'path'} = ($1, $2);
	    }
	}

	$$self{'tree'} = $args{'query'}->param('tree') 
	    if $args{'query'}->param('tree');
    }
    if ($args{'tree'}) {
	$$self{'tree'} = $args{'tree'};
    }

    if ($$self{'tree'} =~ s/[+](.+)$//) {
	$$self{'release'} = $1 if $1 ne '*';
    }

    if ($$self{'tree'} and $$self{'tree'} !~ /^[+]/) {
	my $tree = $$self{'tree'};
	return $self
	    unless exists($$config{$tree});

	$$self{'config'} = $$config{$tree};
	$$self{'config'}{'usage'} ||= $$self{'config'}{'index'};
    }

    if (exists $$self{'params'}{'v'} and $$self{'params'}{'v'}) {
	$$self{'release'} ||= $$self{'params'}{'v'}[0]
	    if $$self{'params'}{'v'}[0] ne 'undefined';
	delete($$self{'params'}{'v'});
    }

    if ($$self{'config'}) {
	$$self{'release'} ||= $$self{'config'}{'ver_default'};
	$$self{'release'} ||= $$self{'config'}{'ver_list'}[0];
    }

    return $self;
}

sub read_config {
    my ($self) = @_;

    my $confpath = $LXRng::ROOT.'/lxrng.conf';

    if ($cached_config) {
	my @stat = stat($confpath);
	if (@stat and
	    $stat[9] == $cached_config_stat and 
	    time - $cached_config_age < 3600)
	{
	    return $cached_config;
	}
	$cached_config_stat = $stat[9];
	$cached_config_age = time;
    }

    if (open(my $cfgfile, $confpath)) {
	my @config = eval("use strict; use warnings;\n".
			  "#line 1 \"configuration file\"\n".
			  join("", <$cfgfile>));
	die($@) if $@;

	die("Bad configuration file format\n")
	    unless @config == 1 and ref($config[0]) eq 'HASH';

	$cached_config = $config[0];
	return $config[0];
    }
    else {
	die("Couldn't open configuration file \"$confpath\".");
    }
}

sub release {
    my ($self, $value) = @_;

    $$self{'release'} = $value if @_ == 2;
    return $$self{'release'};
}

sub default_release {
    my ($self, $value) = @_;

    return $$self{'config'}{'ver_default'};
}

sub all_releases {
    my ($self) = @_;

    return $$self{'config'}{'ver_list'};
}

sub param {
    my ($self, $key) = @_;
    my @res;

    @res = @{$$self{'params'}{$key}} if
	exists $$self{'params'}{$key};

    return wantarray ? @res : $res[0];
}

sub path {
    my ($self, $value) = @_;

    $$self{'path'} = $value if @_ == 2;
    return $$self{'path'};
}

sub tree {
    my ($self) = @_;

    return $$self{'tree'};
}

sub vtree {
    my ($self) = @_;

    if ($self->release ne $self->default_release) {
	return $self->tree.'+'.$self->release;
    }
    else {
	return $self->tree;
    }
}

sub path_elements {
    my ($self) = @_;

    return [] if $self->path =~ /^[ +]/;

    my @path;
    return [map {
	push(@path, $_); { 'node' => $_, 'path' => join('', @path) }
    } $self->path =~ m,([^/]+\/?),g];
}

sub config {
    my ($self) = @_;

    return $$self{'config'} || {};
}

sub prefs {
    my ($self) = @_;

    return $$self{'prefs'};
}

sub base_url {
    my ($self, $notree) = @_;

    my $base = $self->config->{'base_url'};
    unless ($base) {
	$base = $$self{'req_base'};
    }

    $base =~ s,/*$,/,;

    return $base if $notree;

    $base .= $self->vtree.'/';
    $base =~ s,/+$,/,;

    return $base;
}

sub args_url {
    my ($self, %args) = @_;

    # Todo: escape
    my $args = join(';', map { $_.'='.$args{$_} } keys %args);
    $args = '?'.$args if $args;
    return $args;
}
    
1;
