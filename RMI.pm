package Net::RMI;
require 5.004;

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK $PORT $data);
use Carp;

require Exporter;

@ISA = qw(Exporter);
@EXPORT = qw();
$VERSION = '0.01';
$PORT = 6902;

sub set ($ $ $) {
	my ($self, $parameterName, $parameterValue) = @_;
	if (
		! defined $self		||
		! $self
	) {
		carp "method called directly as function.";
		return;
	}

	my $oldValue =
		(defined $self->{$parameterName}) ?
			$self->{$parameterName}
		:
			""
	;

	$self->{$parameterName} = $parameterValue;

	return $oldValue;
}

sub get ($ $) {
	my ($self, $parameterName) = @_;
	if (
		! defined $self		||
		! $self
	) {
		carp "method called directly as function.";
		return;
	}

	my $parameterValue =
		(defined $self->{$parameterName}) ?
			$self->{$parameterName}
		:
			""
	;

	return $parameterValue;
}

### UTILITY FUNCTIONS ###

sub stripEOLN ($) {
	my ($string) = @_;
	$string =~ s/\x0a$//g;
	return $string;
}

sub serialize ($) {
	my ($data) = @_;

	if (! defined $data || ! $data) {
		return "S[0]";
	}

	my $list;

	if (! ref($data)) {
		my $length = length($data);
		$list .= "S[$length]";
		$list .= $data;
	}
	elsif (UNIVERSAL::isa($data, "SCALAR")) {
		my $length = length($$data);
		$list .= "S[$length]";
		$list .= $$data;
	}
	elsif (UNIVERSAL::isa($data, "ARRAY")) {
		my $length = @$data;
		$list .= "A[$length]";
		for (my $i = 0; $i < $length; $i++) {
			my $value = $$data[$i];
			if (ref($value)) {
				$list .= &serialize($value);
			} else {
				$list .= &serialize(\$value);
			}
		}
	}
	elsif (UNIVERSAL::isa($data, "HASH")) {
		my @keys = keys %$data;
		my $length = @keys;
		$list .= "H[$length]";
		foreach my $key(@keys) {
			my $value = $$data{$key};
			if (ref($key)) {
				$list .= &serialize($key);
			} else {
				$list .= &serialize(\$key);
			}
			if (ref($value)) {
				$list .= &serialize($value);
			} else {
				$list .= &serialize(\$value);
			}
		}
	}

	return $list;
}

sub deserialize ($) {
	local ($data) = @_;
	my $context = substr($data, 0, 1);
	my $response = &do_deserialize(1);
	return $$response[0];
}

sub do_deserialize {
	my ($limit) = @_;
	$limit = 1 if (! defined $limit);
	my @items;
	my $found = 0;

	while (($found < $limit) && ($data =~ /^([SAH])\[(\d+)\](.+$)/)) {
		$found++;
		my $type = $1;
		my $length = $2;
		$data = $3;
		if ($type eq "S") {
			my $value = substr($data, 0, $length);
			$data = substr($data, $length);
			push @items, $value;
		}
		elsif ($type eq "A") {
			push @items, &do_deserialize($length);
		}
		elsif ($type eq "H") {
			my %th = @{ &do_deserialize($length * 2) };
			push @items, \%th;
		}
	}

	return \@items;
}

1;
__END__

=head1 NAME

Net::RMI - Perl Remote Method Invocation (RMI) base class and utilities.


=head1 SYNOPSIS

	$d = serialize(\%sourceData);

	%destinationData = %{ deserialize($d) };


=head1 DESCRIPTION

This is the base class for Perl RMI. It provided some basic methods
common to both the client and server, and provides for data
serialization.

=head1 METHODS

=over 4

=item B<set>

Sets an object's parameter to the specified value.

	Parameters: the parameter's name and value.
	Returns: nothing.


=item B<get>

Gets an object's parameter value.

	Parameters: the parameter's name.
	Returns: the parameter's value.


=item B<stripEOLN>

Removes a SINGLE traling 0x0A (LF) character from the end of a scalar.

	Parameters: a scalar.
	Returns: a scalar.


=item B<serialize>

Serializes an arbitrarily deep (or shallow for that matter) Perl data
structure into a scalar.

	Parameter: a reference to a scalar, array, or hash.
	Returns: a scalar containing the serialized data.


=item B<deserialize>

Converts a scalar containing serialized data back into the data structures
it represents.

	Parameters: a scalar containing the serialized data.
	Returns: a reference to a scalar, array, or hash.


=back

=head1 SEE ALSO

L<Net::RMI::Server>, and L<Net::RMI::Client>.


=head1 AUTHOR

Stephen Pandich, pandich@yahoo.com

=begin html

<a HREF="mailto:pandich@yahoo.com">Contact the Author</a>

=end

=cut
