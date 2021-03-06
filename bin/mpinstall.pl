#!C:/Perl/bin
#####################################################################
# A Perl script to fetch and install via ppm mod_perl on Win32
# Copyright 2002, by Randy Kobes.
# This script may be distributed under the same terms as Perl itself.
# Please report problems to Randy Kobes <randy@theoryx5.uwinnipeg.ca>
#####################################################################

use strict;
use warnings;
use ExtUtils::MakeMaker;
use LWP::Simple;
use File::Copy;
use Config;
use Safe;
use Digest::MD5;
require Win32;
require File::Spec;

die "This only works for Win32" unless $^O =~ /Win32/i;
die "No mod_perl ppm package available for this Perl" if ($] < 5.006001);

my ($apache2, $apache, $apache22);
my @drives = drives();

# find a possible Apache2 directory
APACHE2: {
    for my $drive (@drives) {
        for my $p ('Apache2', 'Program files/Apache2', 
                   'Program Files/Apache Group/Apache2') {
            my $candidate = File::Spec->catpath($drive, $p);
            if (-d $candidate) {
                $apache2 = $candidate;
                last APACHE2;
            }
        }
    }
}
if ($apache2) {
    $apache2 = fix_path($apache2);
    my $ans = prompt(qq{Install mod_perl-2 for "$apache2"?}, 'yes');
    $apache2 = undef unless ($ans =~ /^y/i);
}

# if no Apache2, try to find Apache1
unless ($apache2) {
  APACHE: {
        for my $drive (@drives) {
            for my $p ('Apache', 'Program Files/Apache', 
                       'Program Files/Apache Group/Apache') {
                my $candidate = File::Spec->catpath($drive, $p);
                if (-d $candidate) {
                    $apache = $candidate;
                    last APACHE;
                }
            }
        }
    }
}
if ($apache) {
    $apache = fix_path($apache);
    my $ans = prompt(qq{Install mod_perl 1 for "$apache"?}, 'yes');
    $apache = undef unless ($ans =~ /^y/i);
}

# check Apache versions 
if ($apache or $apache2) {
    my $vers;
    if ($apache) {
        $vers = qx{"$apache/apache.exe" -v};
        die qq{"$apache" does not appear to be version 1.3}
            unless $vers =~ m!Apache/1.3!;
    }
    else {
        my $vers;
        for my $binary(qw(Apache.exe httpd.exe)) {
            my $b = File::Spec->catfile($apache2, 'bin', $binary);
            next unless -x $b;
            $vers = qx{$b -v};
            last;
	}
        die qq{Cannot determine the Apache version} unless $vers;
        die qq{"$apache2" does not appear to be version 2.x}
            unless $vers =~ m!Apache/2.!;
        $apache22 = 1 if $vers =~ m!Apache/2.2!;
    }
}
# prompt to get an Apache installation directory
else {
    my $dir = prompt("Where is your apache installation directory?", '');
    die 'Need to specify the Apache installation directory' unless $dir;
    $dir = fix_path($dir);
    die qq{"$dir" does not exist} unless (-d $dir);
    if ($dir =~ /Apache2/) {
        my $ans = prompt(qq{Install mod_perl 2 for "$dir"?}, 'yes');
        $apache2 = $dir if ($ans =~ /^y/i);
    }
    else {
        my $ans = prompt(qq{Install mod_perl 1 for "$dir"?}, 'yes');
        $apache = $dir if ($ans =~ /^y/i);
    }
    unless ($apache or $apache2) {
        my $mpv = prompt('Which mod_perl version would you like [1 or 2]?', 2);
        if ($mpv == 1) {
            $apache = $dir;
        }
        elsif ($mpv == 2) {
            $apache2 = $dir;
        }
        else {
            die 'Please specify either "1" or "2"';
        }
    }
}

die 'Please specify an Apache directory' unless ($apache or $apache2);
my $theoryx5 = 'http://theoryx5.uwinnipeg.ca';
my $ppms = $theoryx5 . '/ppms/';
my $ppmsx86 = $ppms . 'x86/';
my $ppmpackages = $theoryx5 . '/ppmpackages/';
my $ppmpackagesx86 = $ppmpackages . 'x86/';
my ($ppd, $tgz, $ppdfile, $tgzfile, $checksums, $so_fetch, $so_fake);
my $so = 'mod_perl.so';
my $cs = 'CHECKSUMS';

# set appropriate ppd and tar.gz files
if ($] < 5.008) {
    $checksums = $ppmpackagesx86 . $cs;
    if ($apache2) {
        die 'No mod_perl 2 package available for this perl version';
    }
    else {
        my $ans = prompt('Do you need EAPI support for mod_ssl?', 'no');
        if ($ans =~ /^n/i) {
            $ppdfile = 'mod_perl.ppd';
            $tgzfile = 'mod_perl.tar.gz';
            $so_fake = 'mod_perl.so';
        }
        else {
            $ppdfile = 'mod_perl-eapi.ppd';
            $tgzfile = 'mod_perl-eapi.tar.gz';
            $so_fake = 'mod_perl-eapi.so';
        }
        $ppd = $ppmpackages . $ppdfile;
        $tgz = $ppmpackagesx86 . $tgzfile;
        $so_fetch = $ppmpackagesx86 . $so_fake;
    }
}
else {
    $checksums = $ppmsx86 . $cs;
    if ($apache2) {
        my $ans = prompt('Do you want the latest mod_perl 2 development version?', 'no');
        if ($ans =~ /^n/i) {
            if ($apache22) {
                $ppdfile = 'mod_perl-2.2.ppd';
                $tgzfile = 'mod_perl-2.2.tar.gz';
                $so_fake = 'mod_perl-2.2.so';
            }
            else {
                $ppdfile = 'mod_perl.ppd';
                $tgzfile = 'mod_perl.tar.gz';
                $so_fake = 'mod_perl.so';
            }
        }
        else {
            $ppdfile = 'mod_perl-dev.ppd';
            $tgzfile = 'mod_perl-dev.tar.gz';
            $so_fake = 'mod_perl-dev.so';
        }
        $ppd = $ppms . $ppdfile;
        $tgz = $ppmsx86 . $tgzfile;
        $so_fetch = $ppmsx86 . $so_fake;
    }
    else {
        my $ans = prompt('Do you need EAPI support for mod_ssl?', 'no');
        if ($ans =~ /^n/i) {
            $ppdfile = 'mod_perl-1.ppd';
            $tgzfile = 'mod_perl-1.tar.gz';
            $so_fake = 'mod_perl-1.so';
        }
        else {
            $ppdfile = 'mod_perl-eapi-1.ppd';
            $tgzfile = 'mod_perl-eapi-1.tar.gz';
            $so_fake = 'mod_perl-eapi-1.so';
        }
        $ppd = $ppms . $ppdfile;
        $tgz = $ppmsx86 . $tgzfile;
        $so_fetch = $ppmsx86 . $so_fake;
    }
}

my $tmp = $ENV{TEMP} || $ENV{TMP} || '.';
chdir $tmp or die "Cannot chdir to $tmp: $!";

# fetch the ppd and tar.gz files
print "Fetching $ppd ...";
getstore($ppd, $ppdfile);
print " done!\n";
die "Failed to fetch $ppd" unless -e $ppdfile;
print "Fetching $tgz ...";
getstore($tgz, $tgzfile);
print " done!\n";
die "Failed to fetch $tgz" unless -e $tgzfile;
print "Fetching $so_fetch ...";
getstore($so_fetch, $so_fake);
print " done!\n";
die "Failed to fetch $so_fetch" unless -e $so_fake;
print "Fetching $checksums ...";
getstore($checksums, $cs);
print " done!\n";
die "Failed to fetch $checksums" unless -e $cs;

# check CHECKSUMS for the tar.gz and so files
my $cksum = load_cs($cs);
die "Could not load $cs: $!" unless $cksum;
die qq{CHECKSUM check for "$tgzfile" failed.\n} 
    unless (verifyMD5($cksum, $tgzfile));
die qq{CHECKSUM check for "$so_fake" failed.\n}
    unless (verifyMD5($cksum, $so_fake));
unless ($so_fake eq $so) {
    rename($so_fake, $so) or die "Rename of $so_fake to $so failed: $!";
}

# edit the ppd file to reflect a local installation
my $old = $ppdfile . '.old';
rename ($ppdfile, $old) 
    or die "renaming $ppdfile to $old failed: $!";
open(my $oldfh, $old) or die "Cannot open $old: $!";
open(my $newfh, ">$ppdfile") or die "Cannot open $ppdfile: $!";
while (<$oldfh>) {
    next if /<INSTALL/;
    s/$tgz/$tgzfile/;
    print $newfh $_;
}
close $oldfh;
close $newfh;

# install mod_perl via ppm
my $ppm = $Config{bin} . '\ppm';
my @args = ($ppm, 'install', $ppdfile);
print "\n@args\n";
system(@args) == 0 or die "system @args failed: $?";

# figure out where to place mod_perl.so
my $modules = $apache ? "$apache/modules" : "$apache2/modules";
$modules = prompt("Where should $so be placed?", $modules);
die "Please install $so to your Apache modules directory manually"
    unless $modules;
$modules = fix_path($modules);

unless (-d $modules) {
    my $ans = prompt(qq{"$modules" does not exist. Create it?}, 'yes');
    if ($ans =~ /^y/i) {
        mkdir $modules or die "Cannot create $modules: $!";
    }
    else {
        $modules = undef;
    }
}
# move mod_perl.so to the Apache modules directory
if ($modules) {
    print "\nMoving $so to $modules ...";
    move($so, qq{$modules})
        or die "Moving $so to $modules failed: $!";
    print " done!\n";
}
else {
    die "Please install $so to your Apache modules directory manually"
}

# clean up, if desired
my $ans = prompt("Remove temporary installation files from $tmp?", 'yes');
if ($ans =~ /^y/i) {
    unlink ($ppdfile, $old, $tgzfile, $cs, $so) 
        or warn "Cannot unlink files from $tmp: $!";
}

# get the name and location of the perlxx.dll
(my $dll = $Config{libperl}) =~ s!\.lib$!.dll!;
$dll = $Config{bin} . '/' . $dll;
$dll =~ s!\\!/!g;

# suggest a minimal httpd.conf configuration
my $ap = $apache || $apache2;
print <<"END";

mod_perl was successfully installed.
To try it out, put the following directives in your
Apache httpd.conf file (under $ap/conf):
    
LoadFile "$dll"
LoadModule perl_module modules/$so

in the section where other apache modules are loaded.
You may also have to add $Config{bin}
to your PATH environment variable.
    
For more information, visit http://perl.apache.org/.

END

# routine to verify the CHECKSUMS for a file
# adapted from the MD5 check of CPAN.pm

sub load_cs {
    my $cs = shift;
    my ($cksum, $fh);
    unless (open $fh, $cs) {
        warn "Could not open $cs: $!";
        return;
    }
    local($/);
    my $eval = <$fh>;
    $eval =~ s/\015?\012/\n/g;
    close $fh;
    my $comp = Safe->new();
    $cksum = $comp->reval($eval);
    if ($@) {
        warn $@;
        return;
    }
    return $cksum;
}

sub verifyMD5 {
    my ($cksum, $file) = @_;
    my ($fh, $is, $should);
    unless (open($fh, $file)) {
        warn "Cannot open $file: $!";
        return;
    }
    binmode($fh);
    unless ($is = Digest::MD5->new->addfile($fh)->hexdigest) {
        warn "Could not compute checksum for $file: $!";
        close($fh);
        return;
    }
    close($fh);
    if ($should = $cksum->{$file}->{md5}) {
        my $test = $is eq $should ? 1 : 0;
        printf qq{Checksum for "$file" is %s\n}, 
            ($test == 1) ? 'OK.' : 'NOT OK.';
        return $test;
    }
    else {
        warn "Checksum data for $file not present in CHECKSUMS.\n";
        return;
    }
}

sub fix_path {
    my $file = shift;
    $file = Win32::GetShortPathName($file);
    $file =~ s!\\!/!g;
    return $file;
}

sub drives {
    my @drives = ();
    eval{require Win32API::File;};
    return map {"$_:\\"} ('C' .. 'Z') if $@;
    my @r = Win32API::File::getLogicalDrives();
    return unless @r > 0;
    for (@r) {
        my $t = Win32API::File::GetDriveType($_);
        push @drives, $_ if ($t == 3 or $t == 4);
    }
    return @drives > 0 ? @drives : undef;
}
