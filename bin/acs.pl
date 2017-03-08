#!/usr/bin/perl -w

# acs.pl
#
# 06/18/07 09:19:54 CEST Dobrica Pavlinusic <dpavlin@rot13.org>

use strict;

use lib './lib';
use CWMP::Server;
use CWMP::Session;
use Getopt::Long;
use Data::Dump qw/dump/;
use File::Find;

#use Devel::LeakTrace::Fast;

my $port = 3333;
my $debug = 0;
my $store_path = './';
my $store_plugin = 'YAML';
my $create_dump = 1;
my $dump_dir = 'dump/';

GetOptions(
	'debug+' => \$debug,
	'port=i' => \$port,
	'store-path=s' => \$store_path,
	'store-plugin=s' => \$store_plugin,
	'create-dump!' => \$create_dump,
	'dump-dir=s' => \$dump_dir,
);

if ( $create_dump ) {
	warn "## cleaning dump directory\n" if $debug;
	if ( -e $dump_dir ) {
		find({
			wanted => sub {
				my $path = $File::Find::name;
				return if -d $path;
				unlink($path) || die "can't remove $path: $!";
				warn "## removed $path\n" if $debug;
			},
			no_chdir => 1,
		}, $dump_dir );
	} else {
		mkdir $dump_dir;
	}
}

my $server = CWMP::Server->new({
	port => $port,
	session => {
		store => {
			module => $store_plugin,
			path => $store_path,
			debug => $debug,
		},
		create_dump => $create_dump,
	},
	debug => $debug,
});

$server->run();

