BEGIN {
	$| = 1;
	$loaded = 0;
	print "Running tests 1..3\n";
	$child = 0;
}

END {
	print "not ok 1\n" unless $loaded;
	kill 9, $child if ($child);
}

use Net::RMI;
use Net::RMI::Server;
use Net::RMI::Client;
$loaded = 1;
print "ok 1\n";

sub add2Numbers ($$) {
	my ($n1, $n2) = @_;
	my $n3 = ($n1 + $n2);
	return \$n3;
}


sub client {
	my $client = new Net::RMI::Client("localhost");
	$client->pollAllServers();
	$result = $client->RM_add2Numbers(7, 12);
	return ($result == 19);
}

sub server {
	my $s = new Net::RMI::Server || return 0;
	my $function = "add2Numbers";
	$s->registerFunction($function, \&$function, ['$', '$'], '$');
	$s->listen() if (!($child = fork()));
	return 1;
}

if (&server()) {
	print "ok 2\n";
} else {
	print "not ok 2\n";
	exit(1);
}

sleep(2);
if (&client()) {
	print "ok 3\n";
} else {
	print "not ok 3\n";
	exit(1);
}
