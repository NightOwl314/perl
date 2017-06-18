#!perl

use strict;
use warnings;

eval {
    unless (Win32::IsWin95()) {
	die "This is only for Windows 9x!\n";
    }    
    unless ($ENV{winbootdir}) {
	die "No winbootdir environment variable!  That sucks!\n";
    }
    my $autoexec = substr($ENV{winbootdir},0,2) .'\autoexec.bat';
    my $perl = $^X;
    $perl =~ s|\\.?perl.exe$||i;

    if (-e $autoexec && ! -w $autoexec) {
	chmod 0755, $autoexec
	    or die "Unable to set $autoexec for writing: $!\n";
    }
        
    open(F, ">>$autoexec") 
	or die "Unable to open $autoexec for writing: $!\n";

    print F "\nSET PATH=$perl;%PATH%\n";

    close F
	or die "Error closing filehandle: $!\n";
};
warn $@ if $@;

    
 
