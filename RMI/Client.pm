package Net::RMI::Client;
require 5.004;

use strict;
no strict qw(refs);
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK $DEBUG);
use Net::RMI;
use Carp;
use IO::Socket;

require Exporter;

@ISA = qw(Exporter Net::RMI);
@EXPORT = qw();
@EXPORT_OK = qw();
$DEBUG = 0;

my $DEFAULT_TIMEOUT_SECONDS = 60;

sub AUTOLOAD {
	my ($self, @args) = @_;
	use vars qw($AUTOLOAD);

	if ($AUTOLOAD =~ /^.+::RM_(.+)$/) {
		my $function = $1;
		my @inParams;
		my @outParams;

		map {
			if (ref($_)) {
				push @inParams, $_;
			} else {
				push @inParams, \$_;
			}
		} @args;

		my ($server, $port, $params, $returns) = $self->getFunction($function);

		for (my $currentParam = 0; $currentParam < @$params; $currentParam++) {
			my $param = $$params[$currentParam];
			my $givenParam = ref($inParams[$currentParam]);

			if (
				(($param eq '%') && ($givenParam ne "HASH"))	||
				(($param eq '@') && ($givenParam ne "ARRAY"))	||
				(($param eq '$') && ($givenParam ne "SCALAR"))
			) {
				carp "Type mismatch in argument $currentParam.\n";
				return;
			}
			push @outParams, Net::RMI::serialize($inParams[$currentParam]);
		}

		my $client = new IO::Socket::INET(
			PeerAddr	=>	$server,
			PeerPort	=>	$port,
			Proto		=>	'tcp'
		);

		if (
			! defined $client	||
			! $client
		) {
			carp "Error: could not connect to $server:$port\n";
			return;
		}

		my $status = Net::RMI::stripEOLN($client->getline());
		if ($status ne "READY") {
			carp "Error: $server:$port not ready.\n";
			return;
		}

		$client->print("exec $function\x0a");
		map { $client->print("$_\x0a") } @outParams;

		my $response = Net::RMI::deserialize(Net::RMI::stripEOLN($client->getline()));
		if ($returns eq '%') {
			return %{ $response };
		}
		elsif ($returns eq '@') {
			return @{ $response };
		}
		else {
			return $response;
		}

	}
}

sub new ($@) {
	my($class, @serverList) = @_;
	if (
		! defined $class	||
		! $class
	) {
		return;
	}

	my $self = {};
	bless $self, $class;

	if (
		defined @serverList	&&
		@serverList
	) {
		$self->addServer(@serverList);
	}

	return $self;
}

sub addServer ($@) {
	my ($self, @serverList) = @_;

	foreach my $serverEntry(@serverList) {
		$self->{'serverTable'}{$serverEntry}{$Net::RMI::PORT} = 1;
		$self->pollServer($serverEntry, $Net::RMI::PORT);
	}
}

sub addServerFunction ($$$$$) {
	my ($self, $server, $port, $function, $params, $returns) = @_;
	print "Adding $function from $server.\n" if ($DEBUG);
	$self->{'serverTable'}{$server}{$port}{$function}{'params'} = $params;
	$self->{'serverTable'}{$server}{$port}{$function}{'returns'} = $returns;
	$self->{'functionTable'}{$function}{$server}{$port} = 0;
}

sub getFunction ($$) {
	my ($self, $function) = @_;
	if (! defined $self->{'functionTable'}{$function}) {
		croak "Error: function '$function' not available.\n";
		return;
	}

	my $functionTable = $self->{'functionTable'}{$function};
	my $hasToken = 0;

	my @servers = sort keys %$functionTable;
	my $serverCount = @servers;

	my $newServer = $servers[0];
	my $newPort = (sort {$a<=>$b} keys %{ $$functionTable{$newServer} })[0];

	my $currentServer = 0;
	while (!$hasToken && ($currentServer < $serverCount)) {
		my $server = $servers[$currentServer];
		my $portList = $$functionTable{$server};
		my @ports = sort keys %$portList;
		my $portCount = @ports;

		my $currentPort = 0;
		while (!$hasToken && ($currentPort < $portCount)) {
			my $port = $ports[$currentPort];
			$hasToken = $$functionTable{$server}{$port};
			if ($hasToken) {
				$$functionTable{$server}{$port} = 0;
				if ($currentPort < $portCount - 1) {
					$newServer = $server;
					$newPort = $ports[$currentPort + 1];
				} else {
					if ($currentServer < $serverCount - 1) {
						$newServer = $servers[$currentServer + 1];
					} else {
						$newServer = $servers[0];
					}
					$newPort = (sort {$a<=>$b} keys %{ $$functionTable{$newServer} })[0];
				}
			} else {
				$currentPort++;
			}
		}
		$currentServer++ if(! $hasToken);
	}

	my $params = $self->{'serverTable'}{$newServer}{$newPort}{$function}{'params'};
	my @params = split(/\s*,\s*/, $params);
	my $returns = $self->{'serverTable'}{$newServer}{$newPort}{$function}{'returns'};

	return ($newServer, $newPort, \@params, $returns);
}

sub refresh ($) {
	my ($self) = @_;
	$self->pollAllServers;
}

sub pollAllServers ($) {
	my ($self) = @_;

	my $servers = $self->{'serverTable'};

	foreach my $server(sort keys %$servers) {
		foreach my $port(sort { $a <=> $b } keys %{ $$servers{$server} }) {
			$self->pollServer($server, $port);
		}
	}
}

sub pollServer ($$$) {
	my ($self, $server, $port) = @_;

	my $client = new IO::Socket::INET(
		PeerAddr	=>	$server,
		PeerPort	=>	$port,
		Proto		=>	'tcp'
	);

	if (
		! defined $client	||
		! $client
	) {
		carp "Error: could not connect to $server:$port\n";
		return;
	}

	my $status = Net::RMI::stripEOLN($client->getline());
	if ($status ne "READY") {
		carp "Error: $server:$port not ready.\n";
		return;
	}

	$client->print("list\x0a");
	my $functions = Net::RMI::deserialize(Net::RMI::stripEOLN($client->getline()));

	foreach my $function(@$functions) {
		$client->print("get $function\x0a");
		my ($params, $returns) = @{ Net::RMI::deserialize(Net::RMI::stripEOLN($client->getline())) };
		$self->addServerFunction($server, $port, $function, $params, $returns);
	}
	$client->close();
}

1;

__END__

=head1 NAME

Net::RMI::Client - Perl client-side extension for Remote Method Invocation (RMI).

=head1 SYNOPSIS

	use Net::RMI::Client;

	# Initialize the client
	@servers = qw(localhost);
	$client = new Net::RMI::Client(@servers);

	# Refresh it's function list.
	$client->pollAllServers();

	$result = $client->RM_someFunction(@someParameters));

=head1 DESCRIPTION

The client portion of Net::RMI, contains the methods neccessary to
find and invoke remote methods. Remote methods can be invoked explicitly
via the C<$client->RM_someFunction> or implicitly via a more subtly
mechanism:

	sub AUTOLOAD {
		my $function = $AUTOLOAD;
		$function =~ s/^.+::(.+)$/RM_$1/;
		return $client->$function(@_);
	}

	someUnusedFunctionName(@someParameters);

As the AUTOLOAD function will catch this attempt, and forward it to the
Net::RMI::Client instance (in this example called $client).


=head1 METHODS

=over 4

=item B<AUTOLOAD>

This function looks for all functions called that begin with
"RM_". It then attempt to invoke those methods remotely, by
taking all text after the "RM_" and using it as the remote
function name.

	Parameters: none.
	Returns: the results of the RMI.


=item B<new>

The new method creates a new RMI client and defines its initial
list of RMI method servers.

	Parameters: a list of method servers.
	Returns: a new instance.


=item B<addServer>

Adds one or more method servers to the list of servers for this
client.

	Parameters: a list of method servers.
	Returns: nothing.


=item B<addServerFunction>

Adds a specific server, function name pair to the list of available
remote methods for this client.

	Parameters: a server name and port, function name, function's
		parameter list and return-type.
	Returns: nothing.


=item B<getFunction>

Gets a specific server, function name pair based on function name.
If multiple servers provide a function with the same name, they
are picked in round-robin fashion.

	Parameters: the function name.
	Returns: the method server's name and port, the function's
		parameter list and return-type.


=item B<refresh>

An alias for pollAllServers.

(See Below.)


=item B<pollAllServers>

Iterates over all method-servers for this client and retrieves the
information about all functions available on those servers.

	Parameters: none.
	Returns: nothing.


=item B<pollServer>

Retrieves all information, including function parameters and return-type,
for all functions on a specific method-server.

	Parameters: the method-server's name and port.
	Returns: nothing.

=back

=head1 SEE ALSO

L<Net::RMI>, and L<Net::RMI::Server>.


=head1 AUTHOR

Stephen Pandich, pandich@yahoo.com

=begin html

<a HREF="mailto:pandich@yahoo.com">Contact the Author</a>

=end

=cut
