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

package LXRng::Cached;

use strict;
use LXRng;

require Exporter;
use vars qw($memcached @ISA @EXPORT);
@ISA = qw(Exporter);
@EXPORT = qw(cached);

BEGIN {
    eval { require Cache::Memcached;
	   require Storable;
	   require Digest::SHA1;
       };
    if ($@ eq '') {
	my $nspace = substr(Digest::SHA1::sha1_hex($LXRng::ROOT), 0, 8);
	
	$memcached = Cache::Memcached->new({
	    'servers' => ['127.0.0.1:11211'],
	    'namespace' => 'lxrng:$nspace'});
	$memcached = undef 
	    unless ($memcached->set(':caching' => 1))
    }
}

# Caches result from block enclosed by cache { ... }.  File/linenumber
# of the "cache" keyword is used as the caching key.  If additional
# arguments are given after the sub to cache, they are used to further
# specify the caching key.  Otherwise, the arguments supplied to the
# function containing the call to cached are used.

sub cached(&;@);
*cached = \&DB::LXRng_Cached_cached;

package DB;

sub LXRng_Cached_cached(&;@) {
    my ($func, @args) = @_;
    if ($LXRng::Cached::memcached) {
	my ($pkg, $file, $line) = caller(0);
	my $params;
	unless (@args > 0) {
	    my @caller = caller(1);
	    @args = map { UNIVERSAL::can($_, 'cache_key') ? $_->cache_key : $_
			  } @DB::args;
	}
	$params = Storable::freeze(\@args);

	my $key = Digest::SHA1::sha1_hex(join("\0", $file, $line, $params));
	my $val = $LXRng::Cached::memcached->get($key);
	unless ($val) {
	    $val = [$func->()];
	    $LXRng::Cached::memcached->set($key, $val, 3600);
	    # warn "cache miss for $key (".join(":", $file, $line, @args).")\n";
	}
	else {
	    # warn "cache hit for $key\n";
	}
	return @$val;
    }
    else {
	return $func->();
    }
}

1;
