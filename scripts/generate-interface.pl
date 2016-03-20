#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Path qw(mkpath);
use File::Spec;
use Getopt::Long qw(:config gnu_getopt);
use IO::File;
use Pod::Usage qw(pod2usage);

=head1 NAME

generate-interface.pl - generate swig interface files

=head1 SYNOPSIS

generate-interface.pl -m MODULE [options] HEADER...

=head1 OPTIONS

=head2 B<-m>=MODULE, B<--module>=MODULE

REQUIRED - Set module name to MODULE

=head2 B<-f>=REGEX, B<--follow>=REGEX

Only follow includes matching REGEX. Defaults to bitcoin/*.\.hpp

=head2 B<-I>=DIR, B<--include>=DIR

Look for header files in DIR. Defaults to ../*/include

=head2 B<-o>=FILE, B<--outfile>=FILE

Write interface file to FILE. Defaults to STDOUT

=cut

main();


sub main {
    my %opts;
    GetOptions(
        \%opts,
        'include|I=s@',
        'follow|f=s',
        'module|m=s',
        'outfile|o=s',
        'help|h|?',
    ) or pod2usage(-exitval => 1);
    pod2usage(-exitval => 0) if $opts{help};

    unless ($opts{module}) {
        pod2usage(-exitval => 1, -message => '--module is a required option');
    }

    $opts{follow}  ||= qr|\bbitcoin/.*\.h(pp)?|,
    $opts{include} ||= [ glob File::Spec->catdir(qw(.. * include)) ];

    my @targets = @ARGV or pod2usage(-exitval => 1, -message => 'HEADER is required');
    generate_interface(%opts, targets => \@targets);
}

sub generate_interface {
    my (%opts) = @_;
    my $module  = $opts{module};
    my @targets = @{$opts{targets}};
    my %shortened = map {$_ => shorten_header($_, %opts)} @targets;
    my %is_target = map {$_ => 1} values %shortened;

    my $fh;
    if (my $file = $opts{outfile}) {
        my $dir = dirname($file);
        unless (-e $dir) {
            mkpath($dir) or die "Could not create path $dir: $!";
        }
        $fh = IO::File->new($file, 'w') or die "Could not open $file: $!";
    } else {
        $fh = *STDOUT;
    }

    print $fh "%module $module\n";
    print $fh "%{\n";
    print $fh "#include <$_>\n" for map {$shortened{$_}} @targets;
    print $fh "%}\n";
    print $fh "\n";


    $opts{seen} = {};
    my @headers = map {find_headers($_, %opts), $shortened{$_}} @targets;
    for my $header (uniq(@headers)) {
        my $directive = $is_target{$header} ? '%include' : '%import';
        print $fh "$directive <$header>\n";
    }
}

sub find_headers {
    my ($target, %opts) = @_;
    my $seen = $opts{seen} ||= {};
    return if $seen->{$target}++;

    my @includes;
    my $fh = IO::File->new($target, 'r') or die "Could not read $target: $!";
    while (my $line = $fh->getline) {
        my ($header) = $line =~ /^#include\s+['"<]([^'"<>]+)[>"']/ or next;
        next unless $header =~ /$opts{follow}/;

        my $path = resolve_header($header, %opts);
        push @includes, {path => $path, short => $header};
    }
    $fh->close;

    my @headers = map {( find_headers($_->{path}, %opts), $_->{short} )} @includes;
    return uniq(@headers);
}

sub resolve_header {
    my ($header, %opts) = @_;
    return $header if -e $header;

    for my $dir (@{$opts{include}}) {
        my $guess = File::Spec->catfile($dir, $header);
        return $guess if -e $guess;
    }

    die "Could not find $header: checked @{$opts{include}}\n";
}

sub uniq {
    my (@list) = @_;
    my %seen;
    return grep {not($seen{$_}++)} @list;
}

sub shorten_header {
    my ($path, %opts) = @_;
    for my $dir (@{$opts{include}}) {
        my $guess = $path;
        if ($guess =~ s|^$dir/?||) {
            return $guess;
        }
    }
    return $path;
}
