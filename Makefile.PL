# This perl script makes the Makefile

use ExtUtils::MakeMaker;
BEGIN { require 5.004 }

WriteMakefile(
	'NAME'		=>	'Net::RMI',
	'VERSION_FROM'	=>	"RMI.pm",
	'ABSTRACT'	=>	'Perl Remote Method Invocation (RMI)',
	'AUTHOR'	=>	'Stephen Pandich (pandich@yahoo.com)',
	'PM'		=>	{
		'RMI.pm'	=>	'${INST_LIBDIR}/RMI.pm',
		'RMI/Client.pm'	=>	'${INST_LIBDIR}/RMI/Client.pm',
		'RMI/Server.pm'	=>	'${INST_LIBDIR}/RMI/Server.pm'
	}
);
