package Net::RMI::Server;
require 5.004;

use strict;
no strict qw(refs);
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK $DEBUG);
use Net::RMI;
use Carp;
use IO::Socket;
use POSIX qw(:sys_wait_h);

require Exporter;

@ISA = qw(Exporter Net::RMI);
@EXPORT = qw();

$DEBUG = 0;
my $DEFAULT_QUEUE_SIZE = 5;
my $DEFAULT_TIMEOUT_SECONDS = 60;

sub new ($) {
	my($class) = @_;
	if (
		! defined $class	||
		! $class
	) {
		return;
	}

	my $portNumber = $Net::RMI::PORT;
	if (
		! defined $portNumber	||
		$portNumber !~ /^\d+$/	||
		! $portNumber		||
		$portNumber > 2**16
	) {
		carp "invalid port number specified.";
		return;
	}

	my $self = {};
	bless $self, $class;

	$self->set("portNumber", $portNumber);

	return $self;
}

sub listen ($) {
	my ($self) = @_;

	my $socket = new IO::Socket::INET(
		Listen		=>	$DEFAULT_QUEUE_SIZE,
		LocalPort	=>	$self->get("portNumber"),
		Proto		=>	'tcp'
	);


	if (! defined $socket) {
		croak($!);
	}

	$socket->timeout(0);

	$SIG{INT} = sub {
		print "Shutting down.\n" if ($DEBUG);
		$socket.close();
		exit(0)
	};

	print "Accepting connections.\n" if ($DEBUG);
	while(my $client = $socket->accept()) {
		if (fork()) {
			undef $client;
			next;
		}

		print "\t($$) Connection from " . $client->peerhost() . "\n" if ($DEBUG);

		$client->print("READY\x0a");
		my $done = 0;
		do {
			my $command = Net::RMI::stripEOLN($client->getline());
			my $response = "ERROR.";

			if ($command =~ /^QUIT/i) {
				$done = 1;
			}
			elsif ($command =~ /^LIST/i) {
				my @data = $self->listFunctions();
				$response = Net::RMI::serialize(\@data);
			}
			elsif ($command =~ /^GET\s+(\S+)/i) {
				my $functionName = $1;
				my @data = $self->getFunctionInfo($functionName);
				$response = Net::RMI::serialize(\@data);
			}
			elsif ($command =~ /^EXEC\s+(\S+)/i) {
				my $functionName = $1;
				my ($params, $returns) = $self->getFunctionInfo($functionName);
				my $function = $self->getFunction($functionName);
				my @functionParams = ();
				my @params = split(/\s*,\s*/, $params);
				foreach my $param(@params) {
					my $line = Net::RMI::stripEOLN($client->getline);
					push @functionParams, Net::RMI::deserialize($line);
				}

				$response = Net::RMI::serialize(&$function(@functionParams));
			}

			$client->print("$response\x0a") if (! $done);
		} while(! $done);
	
		$client->close();	
		print "\t($$) Connection closed.\n" if ($DEBUG);
		exit(0);
	}
}

sub getFunction ($ $) {
	my ($self, $functionName) = @_;

	my $function = $self->{'functionTable'}{$functionName};
	return $$function{'function'};
}

sub getFunctionInfo ($ $) {
	my ($self, $functionName) = @_;

	my $function = $self->{'functionTable'}{$functionName};
	my $params  = $$function{'params'};
	my $returns = $$function{'returns'};
	return ($params, $returns);
}

sub registerFunction ($ $ \&& \@@ $) {
	my ($self, $functionName, $function, $params, $returns) = @_;
	my $params = join(',', @$params);
	if (defined $self->{'functionTable'}->{$functionName}) {
		carp "Warning: redefinition of function '$functionName'.\n";
	}
	my %data = (
		'function'	=>	$function,
		'returns'	=>	$returns,
		'params'	=>	$params
	);

	$self->{'functionTable'}{$functionName} = \%data;
}

sub listFunctions ($) {
	my ($self) = @_;
	return sort keys %{ $self->{'functionTable'} };
}

### SIGNAL HANDLERS ###

# Stolen from the Perl Cookbook!
sub REAPER {
	1 until (-1 == waitpid(-1, WNOHANG));
	$SIG{CHLD} = \&REAPER;
}
$SIG{CHLD} = \&REAPER;

1;

__END__

=head1 NAME

Net::RMI::Server - Perl server-side extension for Remote Method Invocation (RMI).

=head1 SYNOPSIS

	use Net::RMI::Server;

	$s = new Net::RMI::Server ||
		die "Error: could not create object.\n";

	sub add2Numbers ($$) {
		my ($n1, $n2) = @_;
		return $n1 + $n2;
	}

	$function = "add2Numbers";
	$s->registerFunction($function, \&$function, ['$', '$'], '$');

	$s->listen();


=head1 DESCRIPTION

The server portion of Net::RMI, contains the methods for registering
and serving remotely invoked methods.

Functions may only receive scalars or references. Complex data types
(i.e., arrays and hashes), must be passed by reference. Scalars, may
also be optionally passed by reference.

Functions may only return scalars or references. Complex data types
(i.e., arrays and hashes), must be return as a reference. Scalars, may
also be optionally returned as a reference.

=head1 METHODS

=over 4

=item B<new>

Creates a new method-server.

	Parameters: none.
	Returns: a new instance of this class.


=item B<listen>

Listens forever for remote method requests.

	Parameters: none.
	Returns: never returns.


=item B<getFunction>

Returns a pointer to the function referenced by the function name.

	Parameters: the function's name.
	Returns: a reference to the function code.


=item B<getFunctionInfo>

Returns the "meta-information" about the function reference by the
function name.

	Parameters: the function's name.
	Returns: the function's parameter list and return-type.

=item B<registerFunction>

Register's a local method with this remote-method server.

	Parameters: the function's name, code, parameter list and
		return-list.
	Returns: nothing.


=item B<listFunctions>

	Parameters: none.
	Returns: a list of functions registered to this method-server instance.


=item B<REAPER>

Reaps the zombie children, stolen with thanks from the Perl Cookbook.

	Parameters: none.
	Returns: nothing.

=back


=head1 SEE ALSO

L<Net::RMI>, and L<Net::RMI::Client>.


=head1 AUTHOR

Stephen Pandich, pandich@yahoo.com

=begin html

<a HREF="mailto:pandich@yahoo.com">Contact the Author</a>

=end

=cut
