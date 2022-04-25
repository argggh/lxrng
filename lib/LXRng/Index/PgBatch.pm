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

package LXRng::Index::PgBatch;

# Specialized subclass of LXRng::Index::Pg for doing parallelized
# batched inserts into database.  Higher performance (and higher
# complexity).

use strict;
use DBI;
use POSIX qw(:sys_wait_h);

use base qw(LXRng::Index::Pg);


sub transaction {
    my ($self, $code) =  @_;

    if ($self->dbh->{AutoCommit}) {
	$self->dbh->{AutoCommit} = 0;
	$self->dbh->do(q(set constraints all deferred));
	$code->();
	$self->flush();
	$self->dbh->commit();
	$self->dbh->{AutoCommit} = 1;

	# At end of outermost transaction, wait for outstanding flushes
	$self->_flush_wait();
    }
    else {
	# If we're in a transaction already, don't return to
	# AutoCommit state.
	$code->();

	# Only occasional synchronization if we're inside another
	# transaction.
	# TODO: Check fill grade of caches and flush based on that.
	if ($self->{'writes'}++ % 3259 == 0) {
	    $self->flush();
	    $self->dbh->commit();
	}
    }
}

sub new {
    my ($class, @args) = @_;

    my $self = $class->SUPER::new(@args);
    $$self{'writes'} = 0;
    $$self{'blocks'} = 0;

    return $self;
}

sub flush {
    my ($self) = @_;

    return unless exists($$self{'cache'});

    $self->_flush_wait();

    my $pre = $self->prefix;
    $self->dbh->commit() unless $self->dbh->{AutoCommit};
    my $pid = open($$self{'flush_pipe'}, "-|");
    die("fork failed: $!") unless defined($pid);
    if ($pid == 0) {
	$SIG{'INT'}  = 'IGNORE';
	$SIG{'QUIT'} = 'IGNORE';
	$SIG{'TERM'} = 'IGNORE';
	$SIG{'PIPE'} = 'IGNORE';
	undef $$self{'flush_pipe'};

	my $i = 0;
	my $cache = $$self{'cache'};
	$$self{'dbh'}->{InactiveDestroy} = 1 if $$self{'dbh'};
	undef $$self{'cache'};
	undef $$self{'dbh'};
	# Table list must be ordered wrt foreign constraints.
	foreach my $table (qw(symbols identifiers usage
			      includes filereleases))
	{
	    next unless exists $$cache{$table};
	    my $idx = 0;
	    my $len = $$self{'cache_idx'}{$table};
	    next unless $len > 0;

	    $self->dbh->do(qq{copy $pre$table from stdin});
	    while ($len > 0) {
		$i++;
		my $chunk = substr($$cache{$table}, $idx, $len > 4096 ? 4096 : $len);
		$self->dbh->pg_putline($chunk);
		$idx += 4096;
		$len -= 4096;
	    }
	    $self->dbh->pg_endcopy;
	}
	$self->dbh->commit() unless $self->dbh->{AutoCommit};
	# Analyze after first 1k blocks, then for every 1M block.
	$self->dbh->do(q(analyze)) if
	    (($$self{'blocks'} % 1000000) + $i > 1000000) or
	    (($$self{'blocks'} < 1000) and ($$self{'blocks'} + $i > 1000));

	$self->dbh->disconnect();
	print("$i\n");
	close(STDOUT);
	kill(9, $$);
    }

    foreach my $table (keys %{$$self{'cache_idx'}}) {
	$$self{'cache_idx'}{$table} = 0;
    }

    $$self{'flush_pid'} = $pid;

    warn "*** index: flushing in background\n";
}

sub _flush_wait {
    my ($self) = @_;

    return unless $$self{'flush_pipe'};

    warn "*** index: waiting for running flush to complete...\n";
    $self->dbh->commit() unless $self->dbh->{AutoCommit};
    my $blocks;
    if (sysread($$self{'flush_pipe'}, $blocks, 1024) > 0) {
	$blocks += 0;
	$$self{'blocks'} += $blocks;
	warn "*** index: flushed $blocks blocks\n";
    }
    $$self{'flush_pipe'}->close();
    undef $$self{'flush_pipe'};
    waitpid($$self{'flush_pid'}, 0);
}

sub _add_cached {
    my ($self, $name, $line) = @_;

    unless ($$self{'cache'}{$name}) {
	$$self{'cache'}{$name} = "\0" x 1_000_000;
	$$self{'cache_idx'}{$name} = 0;
    }

    # TODO: flushing here breaks transactional integrity.  Better to
    # extend cache area and let transaction boundary perform
    # flush+commit based on fill grade.
    $self->flush() if
	$$self{'cache_idx'}{$name} + length($line) >
	length($$self{'cache'}{$name});

    substr($$self{'cache'}{$name}, $$self{'cache_idx'}{$name},
	   length($line), $line);
    $$self{'cache_idx'}{$name} += length($line);
}

sub _cached_seqno {
    my ($self, $seqname) = @_;

   unless (exists($$self{'cached_seqno'}{$seqname}) and
	$$self{'cached_seqno'}{$seqname}{'min'} <=
	$$self{'cached_seqno'}{$seqname}{'max'})
    {
	my $dbh = $self->dbh;
	my $pre = $self->prefix;
	my $sth = $$self{'sth'}{'_cached_seqno'}{$seqname} ||=
	    $dbh->prepare(qq{select setval('$pre$seqname',
					   nextval('$pre$seqname')+1000)});
	$sth->execute();
	my ($id) = $sth->fetchrow_array();
	$sth->finish();
	$$self{'cached_seqno'}{$seqname}{'min'} = $id-1000;
	$$self{'cached_seqno'}{$seqname}{'max'} = $id;
    }

    return $$self{'cached_seqno'}{$seqname}{'min'}++;
}

sub _add_include {
    my ($self, $file_id, $inc_id) = @_;

    $self->_add_cached('includes', "$file_id\t$inc_id\n");

    return 1;
}

sub _prime_symbol_cache {
    my ($self) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_prime_symbol_cache'} ||=
	$dbh->prepare(qq{select name, id from ${pre}symbols});
    $sth->execute();
    my %cache;
    while (my ($name, $id) = $sth->fetchrow_array()) {
	$cache{$name} = 0+$id;
    }
    $sth->finish;
    
    $$self{'__symbol_cache'} = \%cache;
}

sub _add_usage {
    my ($self, $file_id, $symbol_id, $lines) = @_;
    
    $self->_add_cached('usage',
		       "$file_id\t$symbol_id\t\{".join(",", @$lines)."}\n");

    return 1;
}

sub _add_symbol {
    my ($self, $symbol) = @_;

    my $id = $self->_cached_seqno('symnum');
    $self->_add_cached('symbols', "$id\t$symbol\n");

    $self->_prime_symbol_cache()
	unless exists $$self{'__symbol_cache'};

    $$self{'__symbol_cache'}{$symbol} = 0+$id;

    return $id;
}

sub _add_ident {
    my ($self, $rfile_id, $line, $sym_id, $type, $ctx_id) = @_;

    $ctx_id = '\\N' unless defined($ctx_id);

    my $id = $self->_cached_seqno('identnum');

    $self->_add_cached('identifiers',
		       join("\t", $id, $sym_id,
			    $rfile_id, $line, $type,
			    $ctx_id)."\n");

    return $id;
}

my $_get_symbol_usage = 0;
sub _get_symbol {
    my ($self, $symbol) = @_;

    unless (exists($$self{'__symbol_cache'})) {
	# Only prime the cache once it's clear that we're likely to
	# hit it a significant number of times.
	return $self->SUPER::_get_symbol($symbol) if
	    $_get_symbol_usage++ < 100;

	$self->_prime_symbol_cache();
    }

    return $$self{'__symbol_cache'}{$symbol} if
	exists $$self{'__symbol_cache'}{$symbol};
    
    return undef;
}

sub _prime_fileid_cache {
    my ($self) = @_;

    my $dbh = $self->dbh;
    my $pre = $self->prefix;
    my $sth = $$self{'sth'}{'_prime_fileid_cache'} ||=
	$dbh->prepare(qq{select path, id from ${pre}files});
    $sth->execute();
    my %cache;
    while (my ($name, $id) = $sth->fetchrow_array()) {
	$cache{$name} = 0+$id;
    }
    $sth->finish;
    
    $$self{'__fileid_cache'} = \%cache;
}

sub _add_file {
    my ($self, $path) = @_;

    my $id = $self->SUPER::_add_file($path);
    $self->_prime_fileid_cache()
	unless exists $$self{'__fileid_cache'};

    $$self{'__fileid_cache'}{$path} = 0+$id;

    return $id;
}

my $_get_file_usage = 0;
sub _get_file {
    my ($self, $path) = @_;

    unless (exists($$self{'__fileid_cache'})) {
	return $self->SUPER::_get_file($path) if
	    $_get_file_usage++ < 500;

	$self->_prime_fileid_cache();
    }

    return $$self{'__fileid_cache'}{$path} if
	exists $$self{'__fileid_cache'}{$path};
    
    return undef;
}

sub _add_filerelease {
    my ($self, $rfile_id, $rel_id) = @_;

    $self->_add_cached('filereleases', "$rfile_id\t$rel_id\n");

    return 1;
}

sub _get_rfile {
    my ($self, $file_id, $revision) = @_;

    my $key = "$file_id\t$revision";
    if (exists($$self{'__revision_epoch_cache'}{$key})) {
	my ($id, $epoch) = split(/\t/, $$self{'__revision_epoch_cache'}{$key});
	return ($id, $epoch);
    }

    my ($id, $epoch) = $self->SUPER::_get_rfile($file_id, $revision);
    if ($id > 0 and $epoch > 0) {
	$$self{'__revision_epoch_cache'}{$key} = "$id\t$epoch";
	$$self{'__revision_id_cache'}{$id} = $key;
    }
    return ($id, $epoch);
}


sub _add_rfile {
    my ($self, $file_id, $revision, $time) = @_;

    my $id = $self->SUPER::_add_rfile($file_id, $revision, $time);
    my ($epoch, $zone) = $time =~ /^(\d+)(?: ([-+]\d\d\d\d)|)$/;

    my $key = "$file_id\t$revision";
    $$self{'__revision_epoch_cache'}{$key} = "$id\t$epoch";
    $$self{'__revision_id_cache'}{$id} = $key;

    return $id;
}

sub _update_rfile_timestamp {
    my ($self, $rfile_id, $time) = @_;
    
    if (exists $$self{'__revision_id_cache'}{$rfile_id}) {
	my $key = $$self{'__revision_id_cache'}{$rfile_id};
	my ($epoch, $zone) = $time =~ /^(\d+)(?: ([-+]\d\d\d\d)|)$/;
	$$self{'__revision_epoch_cache'}{$key} = "$rfile_id\t$epoch";
    }

    return $self->SUPER::_update_rfile_timestamp($rfile_id, $time);
}

sub _to_task {
    my ($self, $rfile_id, $task) = @_;

    my @tasks = qw(indexed referenced hashed);
    unless (exists $$self{'__filestat_cache'}) {
	my $tasks = join('||', map { 
	    qq{(case when $_ then '1' else '0' end)} } @tasks);
	my $dbh = $self->dbh;
	my $pre = $self->prefix;
	my $sth = $$self{'sth'}{'_prime_filestat_cache'} ||=
	    $dbh->prepare(qq{select id_rfile, 1||$tasks
				 from ${pre}filestatus});
	$sth->execute();
	my @cache;
	while (my ($id, $stats) = $sth->fetchrow_array()) {
	    $cache[$id] = 0+$stats;
	}
	$sth->finish;
	
	$$self{'__filestat_cache'} = \@cache;
    }

    if (exists $$self{'__filestat_cache'}[$rfile_id]) {
	my %stat;
	my $flags = $$self{'__filestat_cache'}[$rfile_id];
	@stat{'',@tasks} = split(//, $flags);

	return 0 if $stat{$task};
    }

    return $self->SUPER::_to_task($rfile_id, $task);
}

sub DESTROY {
    my ($self) = @_;

    if ($$self{'dbh'} and ($$self{'dbh_pid'} != $$)) {
	# Don't flush or disconnect inherited db handle.
	$$self{'dbh'}->{InactiveDestroy} = 1;
	undef $$self{'dbh'};
	return;
    }

    # TODO: should not flush outstanding changes if transaction was
    # aborted.
    if ($$self{'writes'} > 0) {
	$self->flush();
	$self->_flush_wait();
    }

    if ($$self{'dbh'}) {
	$$self{'dbh'}->rollback() unless $$self{'dbh'}{'AutoCommit'};
	$$self{'dbh'}->disconnect();
	delete($$self{'dbh'});
    }
}

1;
