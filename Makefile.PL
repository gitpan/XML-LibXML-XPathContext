# $Id: Makefile.PL,v 1.2 2004/04/03 21:00:19 pajas Exp $

use 5.005;

use ExtUtils::MakeMaker;
use Config;
use Symbol;
use File::Spec;

$|=0;

my %config;


# maybe i am doing something wrong here, but on my system parse_fh()
# refuses to work correctly with libxml2 versions below 2.4.25 :|
# (without even a code change at that level)
# someone else should run tests with this package, since i can't 
# trigger this problem. 
my ( $lib_major, $lib_minor, $lib_patch ) = (2, 4, 20);
# uncomment for release?
# my ( $lib_major, $lib_minor, $lib_patch ) = (2, 4, 25);

while($_ = shift) {
    my ($key, $val) = split(/=/, $_, 2);
    $config{$key} = $val;
}

my $DEBUG = delete $config{DEBUG};

# $config{DEFINE} .= " -DXS_WARNINGS";

if ( $] >= 5.006 ) {
    warn "enable native perl UTF8\n";
    $config{DEFINE} .= " -DHAVE_UTF8";
}

# get libs and inc from gnome-config

unless ( $is_Win32 ) {
    eval {
        my $xml2cfg = "xml2-config";
        if ( defined $ENV{XMLPREFIX} ) {
            $xml2cfg = $ENV{XMLPREFIX} . '/bin/' . $xml2cfg;
        }

        print "running xml2-config... ";
        my $ver = backtick("$xml2cfg --version");
        my ($major, $minor, $point) = $ver =~ /(\d+).(\d+)\.(\d+)/g;
        die "VERSION $major.$minor.$point" unless $major > $lib_major
          || ($major == $lib_major && $minor > $lib_minor)
            || ($major == $lib_major && $minor == $lib_minor && $point >= $lib_patch);
        $config{LIBS} ||= backtick("$xml2cfg --libs");
        $config{INC}  ||= backtick("$xml2cfg --cflags");
        print "ok\n";
    };
    if ($@) {
        print "failed\n";
        if ($@ =~ /^VERSION/) {
            die "XML::LibXML needs libxml2 version $lib_major.$lib_minor.$lib_patch or higher (found $@)\n";
        }
        warn "*** ", $@ if $DEBUG;
        warn "using fallback values for LIBS and INC\n";
        # backtick fails if gnome-config didn't exist...
        $config{LIBS} = '-L/usr/local/lib -L/usr/lib -lxml2 -lz -lm';
        $config{INC} = '-I/usr/local/include -I/usr/include';

        print <<OPT;
options:
  LIBS='$config{LIBS}'
  INC='$config{INC}'
If this is wrong, Re-run as:
  \$ $^X Makefile.PL LIBS='-L/path/to/lib' INC='-I/path/to/include'

OPT
    }

    # test for libgdome
    my ( $g_major, $g_minor, $g_patch ) = (0, 7, 3);

    eval {
        print "running gdome-config...";
        my $ver = backtick("gdome-config --version");
        ($major, $minor, $point) = $ver =~ /(\d+).(\d+)\.(\d+)/g;
        die "VERSION " unless $major > $g_major
             || ($major == $g_major && $minor > $g_minor)
             || ($major == $g_major && $minor == $g_minor && $point >= $g_patch) ;
            print "ok\n";
            print "make use of GDOME support\n";
            print "NOTE: You will still have to install XML::GDOME to make\n";
            print "      use of this feature\n";
            $config{LIBS} = backtick("gdome-config --libs");
            $config{INC}  = backtick("gdome-config --cflags");
            $config{DEFINE} .= " -DXML_LIBXML_GDOME_SUPPORT";
    };
    if ($@) {
       print "failed\n";
       print "GDOME support is optional and is not required for running\n";
       print "this package\n";
   }
}


if ($config{LIBS} !~ /\-lxml2\b/) {
    # in this case we are not able to run xml2-config. therefore we need to
    # expand the libz as well.
    $config{LIBS} .= $is_Win32 ? ' -llibxml2 -lzlib' : ' -lxml2 -lz';
}

if ($config{LIBS} !~ /\-lz\b/) {
    # note if libxml2 has not -lz within its cflags, we should not use
    # it! We should trust libxml2 and assume libz is not available on the
    # current system (this is ofcourse not true with win32 systems.
    # $config{LIBS} .= $is_Win32 ? ' -lzlib' :' -lz';
    if ( $config{DEBUG} ) {
        warn "zlib was not configured\n";
        warn "set zlib\n" if $is_Win32;
    }
    $config{LIBS} .= $is_Win32 ? ' -lzlib' :'';
}

if ($config{LIBS} !~ /\-lm\b/) {
    $config{LIBS} .= $is_Win32 ? '' :' -lm';
}

if ( $config{DEBUG} ) {
    warn "win32 compile\n" if $is_Win32;
}

unless (have_library("xml2") or have_library("libxml2")) {
    die <<DEATH;
libxml2 not found
Try setting LIBS and INC values on the command line
Or get libxml2 from 
  http://xmlsoft.org/
If you install via RPMs, make sure you also install the -devel
RPMs, as this is where the headers (.h files) are.
DEATH
}


WriteMakefile( NAME         => 'XML::LibXML::XPathContext',
	       VERSION_FROM => 'XPathContext.pm',
	       PREREQ_PM    => { 'XML::LibXML' => 1.58 },
               # add the DOM extensions to libxml2
               'OBJECT'     => '$(O_FILES)',
               %config,
             );

sub MY::libscan {
    package MY;
    my $self = shift;
    my $path = shift;

    # ignore backup files
    return undef if $path =~ /~/;

    return $self->SUPER::libscan($path);
}


###################################################################
# Functions
#  - these should really be in MakeMaker... But &shrug;
###################################################################

use Config;
use Cwd;
use Symbol;
use File::Spec;

use vars qw/$DEVNULL $is_Win32/;

BEGIN {
    $is_Win32 = ($^O =~ /Win32/);
    if ($is_Win32) {
        $DEVNULL = 'DEVNULL';
    }
    else {
        $DEVNULL = eval { File::Spec->devnull };
        if ($@) { $DEVNULL = '/dev/null' }
    }
}

sub rm_f {
    my @files = @_;
    my @realfiles;
    foreach (@files) {
        push @realfiles, glob($_);
    }
    if (@realfiles) {
        chmod(0777, @realfiles);
        unlink(@realfiles);
    }
}

sub rm_fr {
    my @files = @_;
    my @realfiles;
    foreach (@files) {
        push @realfiles, glob($_);
    }
    foreach my $file (@realfiles) {
        if (-d $file) {
            # warn("$file is a directory\n");
            rm_fr("$file/*");
            rm_fr("$file/.exists");
            rmdir($file) || die "Couldn't remove $file: $!";
        }
        else {
            # warn("removing $file\n");
            chmod(0777, $file);
            unlink($file);
        }
    }
}

sub xsystem {
    my $command = shift;
    if ($DEBUG) {
        print $command, "\n";
        if (system($command) != 0) {
            die "system call to '$command' failed";
        }
        return 1;
    }
    open(OLDOUT, ">&STDOUT");
    open(OLDERR, ">&STDERR");
    open(STDOUT, ">$DEVNULL");
    open(STDERR, ">$DEVNULL");
    my $retval = system($command);
    open(STDOUT, ">&OLDOUT");
    open(STDERR, ">&OLDERR");
    if ($retval != 0) {
        die "system call to '$command' failed";
    }
    return 1;
}

sub backtick {
    my $command = shift;
    if ($DEBUG) {
        print $command, "\n";
        my $results = `$command`;
        chomp $results;
        if ($? != 0) {
            die "backticks call to '$command' failed";
        }
        return $results;
    }
    open(OLDOUT, ">&STDOUT");
    open(OLDERR, ">&STDERR");
    open(STDOUT, ">$DEVNULL");
    open(STDERR, ">$DEVNULL");
    my $results = `$command`;
    my $retval = $?;
    open(STDOUT, ">&OLDOUT");
    open(STDERR, ">&OLDERR");
    if ($retval != 0) {
        die "backticks call to '$command' failed";
    }
    chomp $results;
    return $results;
}

sub try_link0 {
    my ($src, $opt) = @_;
    my $cfile = gensym();
    # local $config{LIBS};
    # $config{LIBS} .= $opt;
    unless (mkdir(".testlink", 0777)) {
        rm_fr(".testlink");
        mkdir(".testlink", 0777) || die "Cannot create .testlink dir: $!";
    }
    chdir(".testlink");
    open($cfile, ">Conftest.xs") || die "Cannot write to file Conftest.xs: $!";
print $cfile <<EOT;
#ifdef __cplusplus
extern "C" {
#endif
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>
#ifdef __cplusplus
}
#endif

EOT
    print $cfile $src;
    print $cfile <<EOT;

MODULE = Conftest          PACKAGE = Conftest

PROTOTYPES: DISABLE

EOT
    close($cfile);
    open($cfile, ">Conftest.pm") || die "Cannot write to file Conftest.pm: $!";
    print $cfile <<'EOT';
package Conftest;
$VERSION = 1.0;
require DynaLoader;
@ISA = ('DynaLoader');
bootstrap Conftest $VERSION;
1;
EOT
    close($cfile);
    open($cfile, ">Makefile.PL") || die "Cannot write to file Makefile.PL: $!";
    print $cfile <<'EOT';
use ExtUtils::MakeMaker;
my %config;
while($_ = shift @ARGV) {
    my ($k, $v) = split /=/, $_, 2;
    warn("$k = $v\n");
    $config{$k} = $v;
}
WriteMakefile(NAME => "Conftest", VERSION_FROM => "Conftest.pm", %config);
EOT
    close($cfile);
    open($cfile, ">test.pl") || die "Cannot write to file test.pl: $!";
    print $cfile <<EOT;
use Test; BEGIN { plan tests => 1; } END { ok(\$loaded) }
use Conftest; \$loaded++;
EOT
    close($cfile);
    my $quote = $is_Win32 ? '"' : "'";
    xsystem("$^X Makefile.PL " . join(' ', map { "${quote}$_=$config{$_}${quote}" } keys %config));

    # I am not shure if OTHERLDFLAGS is really required - at least the
    # libraries to include do not belong here!
    # I would assume a user to set OTHERLDFLAGS in the %config if they are
    # really required. if done so, we don't have to pass them here ...
    xsystem("$Config{make} test ${quote}OTHERLDFLAGS=${opt}${quote}");
} # end try_link0

sub try_link {
    my $start_dir = cwd();
    my $result = eval {
        try_link0(@_);
    };
    warn $@ if $DEBUG && $@;
    chdir($start_dir);
    rm_fr(".testlink");
    return $result;
}

sub have_library {
    my ($lib, $func) = (@_, "blank");
    printf("checking for %s() in -l%s... ", $func, $lib) if $func ne "blank";
    printf("looking for -l%s... ", $lib) if $func eq "blank";

    my $result;
    if ($func) {
        my $libs = $is_Win32 ? " $lib.lib  " : "-l$lib";
#        my $libs = "-l$lib";
        if ($is_Win32) {
            $result = try_link(<<"SRC", undef);
#include <windows.h>
#include <winsock.h>
blank() { return 0; }
int t() { ${func}(); return 0; }
SRC
            unless ($result) {
                $result = try_link(<<"SRC", undef);
#include <windows.h>
#include <winsock.h>
blank() { return 0; }
int t() { void ((*p)()); p = (void ((*)()))${func}; return 0; }
SRC
            }
        }
        else {
            $result = try_link(<<"SRC", undef);
blank() { return 0; }
int t() { ${func}(); return 0; }
SRC
        }
    }

    unless ($result) {
        print "no\n";
        return 0;
    }

    if ($func ne "main") {
        $config{DEFINE} .= uc(" -Dhave_$func");
    }

    print "yes\n";
    return 1;
}
