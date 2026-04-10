#!/usr/bin/perl
use strict;
use warnings;

# ForbCheck Source Scan Engine (Standalone)

my $is_blacklist = ($ENV{BLACKLIST_MODE} eq "true");
my %forbidden = map { $_ => 1 } split(" ", $ENV{BLACKLIST_FUNCS} || "");
my %safe = map { $_ => 1 } split(" ", $ENV{WHITELIST} || "");
my %user_defined = map { $_ => 1 } split(" ", $ENV{USER_FUNCS} || "");
my $allow_mlx = $ENV{ALLOW_MLX} || 0;
my $count = 0;
my $json_mode = ($ENV{USE_JSON} eq "true" || $ENV{USE_HTML} eq "true" || $ENV{USE_GRAPH} eq "true") ? "true" : "false";
my $show_all = ($ENV{SHOW_ALL} eq "true");
my $no_summary = ($ENV{NO_SUMMARY} eq "true");
my %kw_macros = map { $_ => 1 } split(" ", $ENV{KEYWORDS_MACROS} || "");
my %authorized_found = ();

foreach my $file (@ARGV) {
    if (!$is_blacklist && $allow_mlx == 1 && ($file =~ m{/mlx_} || $file =~ m{/mlx/} || $file =~ m{/minilibx/})) {
        next;
    }

    open(my $fh, "<", $file) or next;
    my $content = do { local $/; <$fh> };
    close($fh);
    my @orig_lines = split(/\n/, $content);

    # Anti-quotes and comments
    $content =~ s{(/\*.*?\*/)}{ my $c = $1; my $n = () = $c =~ /\n/g; "\n" x $n }egs;
    $content =~ s{//.*}{}g;
    $content =~ s{("(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27)}{ my $c = $1; my $n = () = $c =~ /\n/g; "\n" x $n }egs;

    my $verbose = ($ENV{VERBOSE} // "") eq "true";
    my @lines = split(/\n/, $content);
    for (my $i = 0; $i < @lines; $i++) {
        my $line = $lines[$i];

        while ($line =~ /\b([a-zA-Z_]\w*)\s*\(/g) {
            my $fname = $1;
            my $is_illegal = 0;

            if (length($fname) <= 2 || $kw_macros{$fname} || $user_defined{$fname}) {
                next;
            }

            if ($is_blacklist) {
                if ($forbidden{$fname}) {
                    $is_illegal = 1;
                } else {
                    $authorized_found{$fname} = 1;
                    next;
                }
            } else {
                if ($safe{$fname} || ($allow_mlx == 1 && $fname =~ /^mlx_/)) {
                    $authorized_found{$fname} = 1;
                    next;
                } else {
                    $is_illegal = 1;
                }
            }

            if ($is_illegal) {
                my $clean_file = $file;
                $clean_file =~ s|^\./||;
                if ($json_mode ne "true") {
                    printf "   \033[31m[FORBIDDEN]\033[0m -> \033[1m%s\033[0m\n", $fname;
                    printf "          \033[33m\xe2\x86\xb3 Location: \033[34m%s:%d\033[0m\n", $clean_file, $i + 1;
                    if ($verbose) {
                        my $snippet = $orig_lines[$i] // "";
                        $snippet =~ s/^\s+//;
                        printf "          \033[33m\xe2\x86\xb3 Code:     \033[36m%s\033[0m\n", $snippet;
                    }
                } else {
                    my $lnum = $i + 1;
                    print "MATCH|-> $fname|in $clean_file:$lnum\n";
                }
                $count++;
            }
        }
    }
}

if ($json_mode ne "true") {
    if ($show_all && keys %authorized_found) {
        foreach my $func (sort keys %authorized_found) {
            printf "   [\033[32mOK\033[0m]         -> %s\n", $func;
        }
    }
    if (!$no_summary) {
        print "\n-------------------------------------------------\n";
        if ($count == 0) {
            print "\t\t\033[32mRESULT: PERFECT\033[0m\n";
        } else {
            printf "\033[31mTotal forbidden functions found: %d\033[0m\n\n", $count;
            print "\t\t\033[31mRESULT: FAILURE\033[0m\n";
        }
    }
}
exit($count > 0 ? 1 : 0);
