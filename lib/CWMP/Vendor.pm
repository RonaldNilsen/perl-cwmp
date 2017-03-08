package CWMP::Vendor;

use strict;
use warnings;

use YAML qw();

#use Carp qw/confess/;
use Data::Dump qw/dump/;

=head1 NAME

CWMP::Vendor - implement vendor specific logic into ACS server

=cut

my $debug = 1;

sub all_parameters {
	my ( $self, $store, $uid, $queue ) = @_;

	my $stored = $store->get_state( $uid );

	return ( 'GetParameterNames', [ 'InternetGatewayDevice.', 1 ] )
		if ! defined $stored->{ParameterInfo};

	my @params =
		map { $stored->{_GetParameterNames}->{$_}++; $_ }
		grep { m/\.$/ && ! exists $stored->{_GetParameterNames}->{$_} }
		keys %{ $stored->{ParameterInfo} }
	;

	if ( @params ) {
		warn "# GetParameterNames ", dump( @params );
		my $first = shift @params;
		delete $stored->{ParameterInfo}->{$first};

		foreach ( @params ) {
			$queue->enqueue( 'GetParameterNames', [ $_, 1 ] );
			delete $stored->{ParameterInfo}->{ $_ };
		}
		$store->set_state( $uid, $stored );

		return ( 'GetParameterNames', [ $first, 1 ] );

	} else {

		my @params = sort
			map { $stored->{_GetParameterValues}->{$_}++; $_ }
			grep { ! exists $stored->{Parameter}->{$_} && ! exists $stored->{_GetParameterValues}->{$_} }
			grep { ! m/\.$/ && ! m/NumberOfEntries/ }
			keys %{ $stored->{ParameterInfo} }
		;

		$store->set_state( $uid, $stored );

		if ( @params ) {
			warn "# GetParameterValues ", dump( @params );
			my $first = shift @params;
			while ( @params ) {
				my @chunk = splice @params, 0, 16; # FIXME 16 seems to be max
				$queue->enqueue( 'GetParameterValues', [ @chunk ] );
			}

			return ( 'GetParameterValues', [ $first ] );
		}
	}

	return;
}

our $tried;

sub some_parameters {
	my ( $self, $store, $uid, $queue ) = @_;

	my $stored = $store->get_state( $uid );

	my $vendor = YAML::LoadFile 'param.yaml';

	$vendor = $vendor->{Parameter} || die  "no Parameter in param.yaml";

	foreach my $n ( keys %$vendor ) {
		printf "We are getting value for $n\n";
		$queue->enqueue( 'GetParameterValues', [ $n ] );	# refresh after change		
	}
	
	return ( 'GetParameterNames', [ 'InternetGatewayDevice.DeviceInfo.',1] ) if ! defined $stored->{ParameterInfo};
	return;
}

sub vendor_config {
	my ( $self, $store, $uid, $queue ) = @_;

	my $stored = $store->get_state( $uid );

	my @refresh;

	my $vendor = YAML::LoadFile 'vendor.yaml';
	$vendor = $vendor->{Parameter} || die  "no Parameter in vendor.yaml";
	$stored = $stored->{Parameter} || warn "no Parameter in stored ", dump($stored);

	warn "# vendor.yaml ",dump $vendor;

	foreach my $n ( keys %$vendor ) {
		if ( ! exists $stored->{$n} ) {
			warn "# $uid missing $n\n";
			push @refresh, $n;
		} elsif ( $vendor->{$n} ne $stored->{$n}
			&& ( ! $tried->{$uid}->{$n}->{set} || $tried->{$uid}->{$n}->{set} ne $vendor->{$n} )
		) {
			my $value = $vendor->{$n};
			if ($stored) {
			  while(
			    $value=~ s/\$\{([^\}]+)\}/$stored->{$1}/gei
			    or
			    $value=~ s/\$\[([^\]]+)\]/eval($1)/gei
			  ) {};
			}
			warn "# set value to $n to be $value\n";
			$queue->enqueue( 'SetParameterValues', { $n => $value } );
			$queue->enqueue( 'GetParameterValues', [ $n ] );	# refresh after change
			push @refresh, $n;
			$tried->{$uid}->{$n}->{set} = $vendor->{$n};
			warn "# set $uid $n $stored->{$n} -> $vendor->{$n}\n";
		} elsif ( $tried->{$uid}->{$n}->{set} eq $vendor->{$n} && $vendor->{$n} ne $stored->{$n} ) {
			warn "ERROR $uid $n $stored->{$n} != $vendor->{$n}\n";
		} else {
			warn "# ok $uid $n = $stored->{$n}\n";
		}
	}

	return ( 'GetParameterValues', [ @refresh ] ) if @refresh;

	warn "# tried ",dump $tried;

	return;
}

1;
