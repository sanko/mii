#!perl
# This is mii2
use v5.38;
use feature 'class', 'try';
no warnings 'experimental::class', 'experimental::builtin';
use Carp           qw[];
use Template::Tiny qw[];        # not in CORE
use Pod::Usage     qw[];
use Capture::Tiny  qw[];        # not in CORE
use Software::License;          # not in CORE
use Software::LicenseUtils;     # not in CORE
use Module::Metadata   qw[];
use Module::CPANfile   qw[];
use Time::Piece        qw[];
use Version::Next      qw[];
use CPAN::Upload::Tiny qw[];    # not in CORE
use List::Util         qw[];
use version 0.77;
#
use App::mii::Markdown;
#
class App::mii v1.0.0 {
    use JSON::PP qw[decode_json];    # not in CORE
    use Path::Tiny qw[];             # not in CORE
    use version    qw[];
    use CPAN::Meta qw[];
    #
    field $path : param : reader //= '.';

    #~ field $package : param //= ();
    #
    field $config : reader;
    field $meta;
    field $trial : reader //= 0;
    #
    field @plugins;
    #
    method abstract( $v    //= () ) { $config->{abstract}    = $v if defined $v; $config->{abstract}; }
    method description( $v //= () ) { $config->{description} = $v if defined $v; $config->{description} }

    method version( $v //= () ) {
        $config->{version} = builtin::blessed $v ? $v : version::parse( 'version', $v ) if defined $v;
        builtin::blessed $config->{version} ? $config->{version} : version::parse( 'version', $config->{version} );
    }

    method name ( $v //= () ) {
        if ( defined $v ) {
            $v =~ s/\.pm\z//i;
            $config->{name} = $v =~ s[::][-]gr;
        }
        $config->{name};
    }
    method distribution () { $config->{name} =~ s[-][::]gr }
    method author ()       { $config->{author} //= [ $self->whoami ] }

    method license ( $v //= () ) {
        if ( defined $v && ref $v eq 'ARRAY' ) {
            $config->{license} = $v;
        }
        map {
            my ($pkg) = Software::LicenseUtils->guess_license_from_meta_key( $_, 2 );
            defined $pkg ? $pkg->new( { holder => _list_and( @{ $self->author } ) } ) :
                $self->log( 'Software::License has no knowledge of "%s"', $_ ) &&
                ()
        } @{ $config->{license} // [] };
    }
    #
    method log ( $msg, @etc ) { say @etc ? sprintf $msg, @etc : $msg; }

    method prompt( $msg, @etc ) {
        $msg .= '> ';
        print @etc ? sprintf $msg, @etc : $msg;
        my $ret = <STDIN>;
        chomp $ret;
        length $ret ? $ret : ();
    }

    method package2path( $package, $base //= 'lib' ) {
        my @path = split '::', $package;
        $path[-1] .= '.pm';
        $path->child($base)->child(@path);
    }
    #
    ADJUST {
        $path = Path::Tiny::path($path)->absolute unless builtin::blessed $path;
        my $meta = $path->child('META.json');
        if ( $meta->exists ) {
            $config = CPAN::Meta->load_file($meta)->as_struct;
            $self->load_plugins();
            $self->trigger('ADJUST');
        }
        else {
            $config = {};
        }
    }

    method gather_files( $release //= 0 ) {    # And spew MANIFEST
        my ($msg) = $self->git( 'ls-files', '--recurse-submodules' );

        # Generate artifacts that must exist before we list files
        $self->spew_meta;
        $self->spew_meta_yml;
        $self->spew_cpanfile;
        $self->spew_license;
        $self->spew_changes($release) if $release;
        my @ignore_pats = map {
            my $p = $_;
            $p = quotemeta($p);
            $p =~ s/\\\*/.*/g;
            $p =~ s/\\\?/./g;
            qr/^$p$/;
        } @{ $config->{'x_ignore'} // [] };
        #
        my @files = grep {
            my $path = "$_";
            $path =~ s{\\}{/}g;
            !List::Util::any { $path =~ $_ } @ignore_pats
        } map { Path::Tiny::path($_)->relative } split /\R+/, $msg;
        push @files, Path::Tiny::path('MANIFEST') unless ( List::Util::any { "$_" eq 'MANIFEST' } @files );
        #
        @files = sort @files;
        #
        $self->trigger( 'gather_files', \@files );
        #
        $path->child('MANIFEST')->spew_raw( join "\n", @files );
        $self->tee( 'tidyall', '-a' );
        return @files;
    }

    method generate_meta() {
        my $stable = !$self->version->is_alpha;
        my $status = $trial ? 'testing' : $stable ? 'stable' : 'unstable';
        exit !$self->log( 'No modules found in ' . $path->child('lib') ) unless $path->child('lib')->children;
        my $provides;
        if ( $stable && $path->child('lib')->children ) {
            my $lib = $path->child('lib');
            $provides = Module::Metadata->provides( dir => $lib->canonpath, version => 2 );

            # Manually find classes that Module::Metadata might have missed (e.g. with attributes)
            $lib->visit(
                sub ( $p, $state ) {
                    return unless $p->is_file && $p->basename =~ /\.pm$/;
                    my $content = $p->slurp_utf8;
                    while ( $content =~ /^[\s\{;]*class\s+([\w:]+)(?:\s+(v?[\d._]+))?.*?[;\{]/mg ) {
                        my ( $pkg, $ver ) = ( $1, $2 );
                        if ( !exists $provides->{$pkg} ) {
                            my $rel = $p->relative($lib)->canonpath;
                            $rel =~ s[\\+][/]g;
                            $provides->{$pkg} = { file => 'lib/' . $rel, ( defined $ver ? ( version => $ver ) : () ) };
                        }
                    }
                },
                { recurse => 1 }
            );
            $_->{file} =~ s[\\+][/]g for values %$provides;

            # Apply no_index filtering
            my $no_index = $config->{no_index} // {};
            for my $pkg ( keys %$provides ) {
                my $file = $provides->{$pkg}{file};

                # Check 'package' exclusion
                if ( my $excl = $no_index->{package} ) {
                    delete $provides->{$pkg} if grep { $pkg eq $_ } @$excl;
                }

                # Check 'directory' exclusion (if file matches path)
                if ( my $dirs = $no_index->{directory} ) {
                    delete $provides->{$pkg} if grep { $file =~ m{^\Q$_\E/} } @$dirs;
                }

                # Check 'file' exclusion
                if ( my $files = $no_index->{file} ) {
                    delete $provides->{$pkg} if grep { $file eq $_ } @$files;
                }
            }
        }
        $_->{file} =~ s[\\+][/]g for values %$provides;
        my %prereqs = (
            configure => {
                requires => {
                    'CPAN::Meta'             => 0,
                    Exporter                 => 5.57,
                    'ExtUtils::Helpers'      => 0.028,
                    'ExtUtils::Install'      => 0,
                    'ExtUtils::InstallPaths' => 0.002,
                    'File::Basename'         => 0,
                    'File::Find'             => 0,
                    'File::Path'             => 0,
                    'File::Spec::Functions'  => 0,
                    'Getopt::Long'           => 2.36,
                    'JSON::PP'               => 2,
                    'Path::Tiny'             => 0,
                    perl                     => 'v5.40.0'
                }
            }
        );
        for my $href ( $path->child('cpanfile')->exists ? Module::CPANfile->load->prereq_specs : (), $config->{prereqs} ) {
            for my ( $stage, $mods )(%$href) {
                for my ( $mod, $version )(%$mods) {
                    $prereqs{$stage}{$mod} = $version;
                }
            }
        }
        $meta = {

            # Retain clutter
            ( map { $_ => $config->{$_} } grep {/^x_/i} keys %$config ),

            # https://metacpan.org/pod/CPAN::Meta::Spec#REQUIRED-FIELDS
            abstract       => $self->abstract // 'Unknown',
            author         => $self->author,
            dynamic_config => $config->{dynamic_config} // 1,                                         # lies
            generated_by   => 'App::mii ' . $App::mii::VERSION,
            license        => [ map { $_->meta_name } $self->license ],
            'meta-spec'    => { version => 2, url => 'https://metacpan.org/pod/CPAN::Meta::Spec' },
            name           => $self->name,
            release_status => $status,
            version        => $self->version->stringify,

            # https://metacpan.org/pod/CPAN::Meta::Spec#OPTIONAL-FIELDS
            description => $config->{description} // $self->description // ' ',
            keywords    => $config->{keywords}    // [],
            no_index    => $config->{no_index}    // { file => [], directory => [], package => [], namespace => [] },
            ( defined $config->{optional_features} ? ( optional_features => $config->{optional_features} ) : () ),
            prereqs   => \%prereqs,
            provides  => $provides,    # blank unless stable
            resources => { ( defined $config->{resources} ? %{ $config->{resources} } : () ), license => [ map { $_->url } $self->license ] },
            #
            x_ignore => [
                List::Util::uniq(
                    ( defined $config->{x_ignore} ? @{ $config->{x_ignore} } : () ),
                    '.tidyallrc', '.gitignore', '.clang-format', '.github/**'
                )
            ],
            #
            sub {
                my @contributors = $self->contributors;
                scalar @contributors ? ( x_contributors => \@contributors ) : ();
            }
                ->()
        };
    }

    method get_repo_url() {

        # Try META resources first
        if ( my $url = $config->{resources}{repository}{web} // $config->{resources}{repository}{url} ) {
            $url =~ s/\.git$//;
            return $url if $url =~ m{^https?://};
        }

        # Try git config
        try {
            my ($url) = $self->git( 'remote', 'get-url', 'origin' );
            if ( defined $url ) {
                chomp $url;

                # Convert git@github.com:User/Repo.git -> https://github.com/User/Repo
                if ( $url =~ s{^(?:git@|https://)([\w\.]+?)[:/](.+?)(\.git)?$}{https://$1/$2} ) {
                    return $url;
                }
            }
        }
        catch ($e) {
            $self->log( 'Error determining repo URL: %s', $e );
        }

        #~ ...;
        '';    # This should never happen...
    }

    method spew_meta ( $out //= $path->child('META.json') ) {    # I could use CPAN::Meta but...
        $out = $path->child($out) unless builtin::blessed $out;
        state $json //= JSON::PP->new->pretty->indent->core_bools->canonical->allow_nonref;
        $out->spew_raw( $json->encode( $self->generate_meta ) ) && return $out;
    }

    method spew_meta_yml( $out //= $path->child('META.yml') ) {
        $out = $path->child($out) unless builtin::blessed $out;
        my $meta = CPAN::Meta->new( $self->generate_meta );
        $meta->save( $out, { version => 1.4 } );
        return $out;
    }

    method spew_changes( $release //= 0, $out //= $path->child('Changes.md') ) {
        $out = $path->child($out) unless builtin::blessed $out;
        my $repo = $self->get_repo_url;
        my $ver  = $self->version;

        # Initialize empty file if missing
        return $out->spew_utf8(<<~"END") unless $out->exists;
                # Changelog

                All notable changes to this project will be documented in this file.

                The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
                and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

                ## [Unreleased]

                ### Added
                  - Initial version

                [Unreleased]: $repo/compare/$ver...HEAD
                [$ver]: $repo/releases/tag/$ver
                END
        return unless $release && !$trial;    # Stop here unless we are finalizing a release
        my $content = $out->slurp_utf8;
        my $date    = Time::Piece::gmtime->strftime('%Y-%m-%d');

        # Header Update: Rename [Unreleased] to [Version] - Date
        # Guard against double-stamping if run multiple times
        unless ( $content =~ m{^## \[\Q$ver\E\]}m ) {
            unless ( $content =~ s{^## \[Unreleased\]}{## [$ver] - $date}m ) {
                $self->log("Warning: Could not find '## [Unreleased]' section in Changes to stamp version $ver");

                # Fallback: Just insert header at top if format is totally broken?
                # Better to warn and do nothing to avoid mangling.
                return;
            }
        }

        # Extract all versions currently in headers (e.g., ## [1.0.0])
        my @versions = $content =~ /^## \[(.+?)\]/gm;

        # Strip existing reference links from bottom (anchored by [ref]: url)
        $content =~ s{^\[.+?\]: http.*(\R|\z)}{}gm;
        $content =~ s{\s+\z}{\n};                     # Trim trailing whitespace
        my $links = "";

        # Link for the next cycle (Unreleased)
        $links .= "[Unreleased]: $repo/compare/$ver...HEAD\n";

        # Link for the current release we just stamped
        if ( @versions > 1 ) {
            my $prev = $versions[1];    # $versions[0] is $ver
            $links .= "[$ver]: $repo/compare/$prev...$ver\n";
        }
        else {
            # First release
            $links .= "[$ver]: $repo/releases/tag/$ver\n";
        }

        # Links for older versions found in the file
        for my $i ( 1 .. $#versions ) {
            my $v = $versions[$i];
            my $p = $versions[ $i + 1 ];
            if ($p) {
                $links .= "[$v]: $repo/compare/$p...$v\n";
            }
            else {
                $links .= "[$v]: $repo/releases/tag/$v\n";
            }
        }
        $out->spew_utf8( $content . "\n" . $links );
    }

    method spew_cpanfile( $out //= $path->child('cpanfile') ) {
        $out = $path->child($out) unless builtin::blessed $out;
        my $cpanfile = Module::CPANfile->from_prereqs( $self->generate_meta->{prereqs} );
        $cpanfile->save($out) && return $out;
    }

    method spew_license( $out //= $path->child('LICENSE') ) {
        $out = $path->child($out) unless builtin::blessed $out;
        $out->spew_raw( join( '-' x 20 . "\n", map { $_->fulltext } $self->license ) ) && return $out;
    }

    method spew_build_pl( $out //= $path->child('Build.PL') ) {
        $out = $path->child($out) unless builtin::blessed $out;
        my $dist = $self->distribution;
        $out->touchpath;
        $out->spew_raw(<<END) && return $out; }
use v5.40;
use lib 'builder';
use ${dist}::Builder;
${dist}::Builder->new->Build_PL();
END

    method spew_builder( $out //= $self->package2path( $self->distribution . '::Builder', 'builder' ) ) {
        $out = $path->child($out) unless builtin::blessed $out;
        my $dist = $self->distribution;
        $out->touchpath;
        $out->spew_raw( <<'END' =~ s[\{\{dist}}][$dist]rg ) && return $out; }
# Based on Module::Build::Tiny which is copyright (c) 2011 by Leon Timmermans, David Golden.
# Module::Build::Tiny is free software; you can redistribute it and/or modify it under
# the same terms as the Perl 5 programming language system itself.
use v5.40;
use feature 'class';
no warnings 'experimental::class';
class    #
    {{dist}}::Builder {
    use CPAN::Meta;
    use ExtUtils::Install qw[pm_to_blib install];
    use ExtUtils::InstallPaths 0.002;
    use File::Basename        qw[basename dirname];
    use File::Find            ();
    use File::Path            qw[mkpath rmtree];
    use File::Spec::Functions qw[catfile catdir rel2abs abs2rel splitdir curdir];
    use JSON::PP 2            qw[encode_json decode_json];

    # Not in CORE
    use Path::Tiny qw[path];
    use ExtUtils::Helpers 0.028 qw[make_executable split_like_shell detildefy];
    #
    field $action : param //= 'build';
    field $meta : reader = CPAN::Meta->load_file('META.json');

    # Params to Build script
    field $install_base : param  //= '';
    field $installdirs : param   //= '';
    field $uninst : param        //= 0;    # Make more sense to have a ./Build uninstall command but...
    field $install_paths : param //= ExtUtils::InstallPaths->new( dist_name => $meta->name );
    field $verbose : param       //= 0;
    field $dry_run : param       //= 0;
    field $pureperl : param      //= 0;
    field $jobs : param          //= 1;
    field $destdir : param       //= '';
    field $prefix : param        //= '';
    #
    ADJUST {
        -e 'META.json' or die "No META information provided\n";
    }
    method write_file( $filename, $content ) { path($filename)->spew_raw($content) or die "Could not open $filename: $!\n" }
    method read_file ($filename)             { path($filename)->slurp_utf8          or die "Could not open $filename: $!\n" }

   method step_build() {
        for my $pl_file ( find( qr/\.PL$/, 'lib' ) ) {
            ( my $pm = $pl_file ) =~ s/\.PL$//;
            system $^X, $pl_file->stringify, $pm and die "$pl_file returned $?\n";
        }

        my %modules       = map { $_ => catfile( 'blib', $_ ) } find( qr/\.pm$/,  'lib' );
        my %docs          = map { $_ => catfile( 'blib', $_ ) } find( qr/\.pod$/, 'lib' );
        my %scripts       = map { $_ => catfile( 'blib', $_ ) } find( qr/(?:)/,   'script' );
        my %sdocs         = map { $_ => delete $scripts{$_} } grep {/.pod$/} keys %scripts;
        pm_to_blib( { %modules, %docs, %sdocs }, catdir(qw[blib lib auto]) );

        #
        mkpath( catdir(qw[blib script]), $verbose );
        for my $src (keys %scripts) {
            my $dest = $scripts{$src};
            my $content = path($src)->slurp_raw;
            $content =~ s{^#!.*perl.*}{#!$^X};
            path($dest)->spew_raw($content);
            make_executable($dest);
        }

        #
        my %dist_shared   = map { $_ => catfile( qw[blib lib auto share dist],   $meta->name, abs2rel( $_, 'share' ) ) } find( qr/(?:)/, 'share' );
        my %module_shared = map { $_ => catfile( qw[blib lib auto share module], abs2rel( $_, 'module-share' ) ) } find( qr/(?:)/, 'module-share' );
        pm_to_blib( { %dist_shared, %module_shared }, catdir(qw[blib lib auto]) );
        mkpath( catdir(qw[blib arch]), $verbose );
        0;
    }
    method step_clean() { rmtree( $_, $verbose ) for qw[blib temp]; 0 }

    method step_install() {
        $self->step_build() unless -d 'blib';
        install(
            [   from_to           => $install_paths->install_map,
                verbose           => $verbose,
                dry_run           => $dry_run,
                uninstall_shadows => $uninst,
                skip              => undef,
                always_copy       => 1
            ]
        );
        0;
    }
    method step_realclean () { rmtree( $_, $verbose ) for qw[blib temp Build _build_params MYMETA.yml MYMETA.json]; 0 }

    method step_test() {
        $self->step_build() unless -d 'blib';
        require TAP::Harness::Env;
        require Config;
        my @libs = map { rel2abs( catdir( 'blib', $_ ) ) } qw[arch lib];
        local $ENV{PERL5LIB} = join( $Config::Config{path_sep}, @libs, ( defined $ENV{PERL5LIB} ? $ENV{PERL5LIB} : () ) );
        my %test_args = (
            ( verbosity => $verbose ),
            ( jobs  => $jobs ),
            ( color => -t STDOUT ),
            lib => [ @libs ],
        );
        TAP::Harness::Env->create( \%test_args )->runtests( sort map { $_->stringify } find( qr/\.t$/, 't' ) )->has_errors;
    }

    method get_arguments (@sources) {
        $_ = detildefy($_) for grep {defined} $install_base, $destdir, $prefix, values %{$install_paths};
        $install_paths = ExtUtils::InstallPaths->new( dist_name => $meta->name );
        return;
    }

    method Build(@args) {
        my $method = $self->can( 'step_' . $action );
        $method // die "No such action '$action'\n";
        exit $method->($self);
    }

    method Build_PL() {
        say sprintf 'Creating new Build script for %s %s', $meta->name, $meta->version;
        $self->write_file( 'Build', sprintf <<'', $^X, __PACKAGE__, __PACKAGE__ );
#!%s
use lib 'builder';
use %s;
use Getopt::Long qw[GetOptionsFromArray];
my %%opts = ( @ARGV && $ARGV[0] =~ /\A\w+\z/ ? ( action => shift @ARGV ) : () );
GetOptionsFromArray \@ARGV, \%%opts, qw[install_base=s install_path=s%% installdirs=s destdir=s prefix=s config=s%% uninst:1 verbose:1 dry_run:1 jobs=i];
%s->new(%%opts)->Build();

        make_executable('Build');
        my @env = defined $ENV{PERL_MB_OPT} ? split_like_shell( $ENV{PERL_MB_OPT} ) : ();
        $self->write_file( '_build_params', encode_json( [ \@env, \@ARGV ] ) );
        if ( my $dynamic = $meta->custom('x_dynamic_prereqs') ) {
            my %meta = ( %{ $meta->as_struct }, dynamic_config => 0 );
            $self->get_arguments( \@env, \@ARGV );
            require CPAN::Requirements::Dynamic;
            my $dynamic_parser = CPAN::Requirements::Dynamic->new();
            my $prereq         = $dynamic_parser->evaluate($dynamic);
            $meta{prereqs} = $meta->effective_prereqs->with_merged_prereqs($prereq)->as_string_hash;
            $meta = CPAN::Meta->new( \%meta );
        }
        $meta->save(@$_) for ['MYMETA.json'];
    }

    sub find ( $pattern, $base ) {
        $base = path($base) unless builtin::blessed $base;
        my $blah = $base->visit(
            sub ( $path, $state ) {
                $state->{$path} = $path if -f $path && $path =~ $pattern;

                #~ return \0 if keys %$state == 10;
            },
            { recurse => 1 }
        );
        values %$blah;
    }
    };
1;
END

    method spew_gitignore( $out //= $path->child('.gitignore') ) {
        $out = $path->child($out) unless builtin::blessed $out;
        my $dist = $self->name;
        $out->spew_raw(<<END) && return $out; }
/.build/
/_build/
/Build
/Build.bat
/blib
/Makefile
/pm_to_blib

/local/
.vs*

nytprof.out
nytprof/

cover_db/

*.bak
*.old
*~

!LICENSE

MANIFEST

/_build_params

MYMETA.*

/${dist}-*

.tidyall.d/
*.gz
*.zip
temp/
t/dev/

eg/*.pl
eg/lib/*.pm

*.session

END

    method spew_tidyall_rc( $out //= $path->child('.tidyallrc') ) {
        $out = $path->child($out) unless builtin::blessed $out;
        $out->spew_raw(<<END) && return $out; }
; Run "tidyall -a" to process all files.
; Run "tidyall -g" to process all added or modified files in the current git working directory.
; https://perladvent.org/2020/2020-12-01.html

ignore = **/*.bak **/_*.pm blib/**/* builder/_alien/**/* extract/**/* dyncall/**/*

[PerlTidy]
select = **/*.{pl,pm,t}
select = cpanfile
argv = -anl -baao --check-syntax --closing-side-comments-balanced -nce -dnl --delete-old-whitespace --delete-semicolons -fs -nhsc -ibc -bar -nbl -ohbr -opr -osbr -nsbl -nasbl -otr -olc --perl-best-practices --nostandard-output -sbc -nssc --break-at-old-logical-breakpoints --break-at-old-keyword-breakpoints --break-at-old-ternary-breakpoints --ignore-old-breakpoints --swallow-optional-blank-lines --iterations=2 --maximum-line-length=150 --paren-vertical-tightness=0 --trim-qw -b -bext=old
;argv = -noll -it=2 -l=100 -i=4 -ci=4 -se -b -bar -boc -vt=0 -vtc=0 -cti=0 -pt=1 -bt=1 -sbt=1 -bbt=1 -nolq -npro -nsfs --opening-hash-brace-right --no-outdent-long-comments -wbb="% + - * / x != == >= <= =~ !~ < > | & >= < = **= += *= &= <<= &&= -= /= |= >>= ||= .= %= ^= x=" --iterations=2

;[PerlCritic]
;select = lib/**/*.pm
;ignore = lib/UtterHack.pm lib/OneTime/*.pm
;argv = -severity 3

[PodTidy]
select = lib/**/*.{pm,pod}
columns = 120

[PodChecker]
select = **/*.{pl,pm,pod}

;[Test::Vars]
;select = **/*.{pl,pl.in,pm,t}

;[PodSpell]
;select = **/*.{pl,pl.in,pm,pod}

[ClangFormat]
select = **/*.{cpp,cxx,h,c,xs,xsh}
ignore = **/ppport.h
; see .clang-format

[YAML]
select = .github/**/*.{yaml,yml}
END

    method spew_compile_t( $out //= $path->child( 't', '000_compile.t' ) ) {
        $out = $path->child($out) unless builtin::blessed $out;
        return $out if $out->exists;
        my $dist = $self->distribution;
        $out->spew_raw(<<END) && return $out;
use v5.40;
use Test2::V0 '!subtest';
use Test2::Util::Importer 'Test2::Tools::Subtest' => ( subtest_streamed => { -as => 'subtest' } );
use lib 'lib', '../lib', 'blib/lib', '../blib/lib';
use ${dist};
#
ok \$${dist}::VERSION, '${dist}::VERSION';

#
done_testing;
END
    }

    method spew_package( $package, $version //= $self->version ) {
        my $file = $self->package2path($package);
        return if $file->exists;
        $file->touchpath;
        my $author      = _list_and( @{ $self->author } );
        my $abstract    = $self->abstract    // '...';
        my $description = $self->description // '...';
        my $license     = '';
        {
            my @licenses = $self->license;
            if ( scalar @licenses > 1 ) {
                $license = "This distribution is covered by the following licenses:\n\n=over\n\n";
                $license .= "=item\n\n" . $_->name . "\n\n" . $_->notice for @licenses;
                $license = "=back\n\n";
            }
            else {
                $license = $licenses[0]->notice;
            }

            # fix email
            $license =~ s[(<|>)]['E<' . ($1 eq '<' ? 'l':'g') . 't>']ge;
            1 while chomp $license;
        }
        $file->touchpath;
        $file->spew_raw(<<END) && $file }
package ${package} ${version} {
    ;
};
1;
__END__
=encoding utf-8

=head1 NAME

${package} - ${abstract}

=head1 SYNOPSIS

    use ${package};
    ...;

=head1 DESCRIPTION

${description}

=head1 See Also

TODO

=head1 LICENSE

${license}

See the F<LICENSE> file for full text.

=head1 AUTHOR

${author}

=begin stopwords


=end stopwords

=cut
END

    method spew_readme_md( $out //= $path->child('README.md') ) {
        $out = $path->child($out) unless builtin::blessed $out;
        my $readme_src;
        if ( defined $config->{x_readme_from} ) {
            $readme_src = $self->path->child( $config->{x_readme_from} );
        }
        if ( !( defined $readme_src && $readme_src->exists ) ) {
            my $pm  = $self->package2path( $self->distribution );
            my $pod = $pm->sibling( $pm->basename('.pm') . '.pod' );
            $readme_src = $pod->exists ? $pod : $pm;
        }
        $out->spew_raw( App::mii::Markdown->new->parse_from_file( $readme_src->canonpath )->as_markdown ) && return $out;
    }

    method spew_tar_gz(
        $verbose //= 0,
        $release //= 0,
        $out     //= Path::Tiny::path(
            $self->name . '-' . $self->version . ( $trial ? '-' . Time::Piece::gmtime->strftime('%Y%m%d%H%M%S') . '-TRIAL' : '' ) . '.tar.gz'
        )->absolute
    ) {
        $out = $path->child($out) unless builtin::blessed $out;
        state $dist;

        #~ return $dist if defined $dist;
        require Archive::Tar;
        my $arch    = Archive::Tar->new;
        my $tar_dir = Path::Tiny->new( $self->name . '-' . $self->version );

        # Determine timestamp for reproducible builds
        my $mtime = $ENV{SOURCE_DATE_EPOCH};
        unless ( defined $mtime ) {
            my ($git_time) = $self->git( 'log', '-1', '--format=%ct' );
            $mtime = $git_time // time;
            chomp $mtime;
        }

        # Add files (listing and filtering is now handled in gather_files)
        $arch->add_data( $tar_dir->child($_)->stringify, $_->slurp_raw, { mtime => $mtime } ) for $self->gather_files($release);
        $_->mode( $_->mode & ~022 ) for $arch->get_files;
        $arch->write( $out->stringify, Archive::Tar::COMPRESS_GZIP() );
        $out->size ? $dist = $out : ();
    }

    method dist(%args) {
        my $verbose = $args{verbose} // 0;
        my $release = $args{pause}   // 0;
        $trial = $args{trial} // 0;
        {
            my $pkg_source;
            if ( defined $config->{x_version_from} ) {
                $pkg_source = $self->path->child( $config->{x_version_from} );
            }
            if ( !( defined $pkg_source && $pkg_source->exists ) ) {
                $pkg_source = $self->package2path( $self->distribution );
            }
            my $info = Module::Metadata->new_from_file($pkg_source);
            $self->version( $info->version );
        }

        #~ eval 'use Test::Spellunker; 1' && Test::Spellunker::all_pod_files_spelling_ok();
        # TODO: Also spell check changelog
        $self->git( 'add', $self->spew_readme_md );
        my $dev_tests  = $path->child( 't', 'dev' );
        my $spelling_t = eval { require Test::Spellunker } ? $dev_tests->child('spellunker.t')->touchpath->spew_raw(<<'') : ();
use Test::Spellunker;
all_pod_files_spelling_ok();

        my $pod_t = eval { require Test::Pod } ? $dev_tests->child('pod.t')->touchpath->spew_raw(<<'') : ();
use Test2::V0;
use Test::Pod;
all_pod_files_ok();
done_testing;


        #~ $self->test($verbose);
        $self->tee( 'tidyall', '-a' );
        $dev_tests->remove_tree( { safe => 0 } );
        $self->spew_tar_gz( $verbose, $release );
    }

    method test(%args) {
        my $verbose = $args{verbose} // 0;
        $self->tee( $^X, 'Build.PL' ) unless -d 'blib';
        $self->tee( $^X, 'Build', 'test' );
    }

    method disttest(%args) {
        my $verbose = $args{verbose} // 0;
        my $dist    = $self->dist(%args);
        my ( $stdout, $stderr, $exit ) = $self->tee( 'cpanm', ( $verbose ? '--verbose' : () ), '--test-only', $dist );
        $exit ? () : $dist;
    }

    method pause_dist( $path, $pause_uri //= 'https://pause.perl.org/pause/authenquery?ACTION=add_uri' ) {
        if ( $config->{x_private} || $config->{x_no_upload} ) {
            $self->log('Blocking upload of private distribution.');
            return ();
        }
        my $dotpause = defined $config->{x_pause_from} ? Path::Tiny::path( $config->{x_pause_from} ) : Path::Tiny::path( (<~>) )->child('.pause');
        exit say <<'END'unless $dotpause->exists;
Please set 'x_pause_from' in META.json or create a '.pause' file in your home directory.

A '.pause' file should look like this:

    user EXAMPLE
    password your-secret-password

See https://metacpan.org/dist/CPAN-Uploader/view/bin/cpan-upload#CONFIGURATION
END
        my $pause = CPAN::Upload::Tiny->new_from_config($dotpause);
        $pause // return;
        $self->log('Uploading...');
        $pause->upload_file($path);
    }

    method git_tag( $tag //= $self->version ) {

        #~ my ( $stdout, $stderr, $exit ) = $self->git(qw[diff --unified=0 --diff-filter=Md  HEAD~.. .\Changes]);
        #~ warn $stdout;
        #~ my @lines = split /\n/, $stdout;
        #~ shift @lines until $lines[0] =~ /^\@\@/;
        $self->git( 'commit', '-am', 'Stable ' . $tag );
        $self->git( 'tag', '-a', $tag, '-m', 'Stable ' . $tag );

        #~ $self->git( 'tag',  '-a',       $tag,     '-m',   '"' . join( "\n", 'Stable ' . $tag, '', map {/^\+(.*)$/} @lines ) . '"' );
        $self->git( 'push', '--atomic', 'origin', 'HEAD', '--tags' );
    }

    method release(%args) {
        $self->version( $args{version} ) if defined $args{version};
        $trial = $args{trial} // 0;
        if ( $config->{x_private} || $config->{x_no_upload} ) {
            $self->log('Blocking release of private distribution.');
            return ();
        }
        {
            my ( undef, undef, $exit ) = $self->git( 'log', '--head' );
            if ( !$exit ) {
                $self->log('Cannot release a dist not backed by a git repo');
                return ();
            }
        }
        $self->check_git_clean();
        $self->run_hook('before_release');
        my ($branch) = $self->git( 'symbolic-ref', '--short', 'HEAD' );
        chomp $branch;
        $self->log( '=' x 50 );
        $self->log( 'Previous version: ' . $self->version );
        $self->log( 'Git branch:       ' . ( $branch eq 'main' ? $branch : "$branch (WARNING: Not main)" ) );
        $self->log( 'Status:           ' . ( $trial            ? 'Trial' : 'Stable' ) );
        $self->log('Changes head:');
        $self->log( '    ' . ( split /\n/, $path->child('Changes.md')->slurp_utf8 )[7] // '???' );
        {    # https://git-scm.com/book/en/v2/Git-Basics-Tagging
            my ( $tag, $stderr, $exit ) = $self->git( 'tag', '-l', $self->version );
            if ( split /\n+/, $tag ) {    # version already tagged in repo
                my ( $taglist, undef, $commits ) = $self->git('tag');
                !$commits or return ();
                my ($ver) = reverse sort map { version::parse( 'version', $_ ) } split /\n+/, $taglist;
                $ver = Version::Next::next_version( $ver->stringify );
                $self->version( $self->prompt( 'Version [%s%s]', $ver, $trial ? '-TRIAL' : '' ) || $ver );
            }
        }
        $self->spew_changes(1);
        $self->tee( 'tidyall', '-a' );
        $self->git( 'add', ( $trial ? () : 'Changes.md' ), 'META.json', 'META.yml' );
        my $tarball = $self->disttest(%args) // die 'Tests failed!';
        $tarball // exit $self->log('Failed to build dist!');
        $args{pause} //= ( ( $self->prompt( 'Upload %s to PAUSE? [N]', Path::Tiny::path($tarball)->basename ) // 'N' ) =~ m[y]i );
        if ( $args{pause} ) {
            $self->pause_dist($tarball);
            $self->git_tag unless $trial;

            # Get things ready for next release
            unless ($trial) {
                my $changes = $path->child('Changes.md');
                my $raw     = $changes->slurp_raw;
                unless ( $raw =~ /## \[Unreleased\]/ ) {
                    $raw =~ s{^(## \[)}{## [Unreleased]\n\n$1}m;
                    $changes->spew_utf8($raw);
                }
            }
            $self->run_hook('after_release');
        }
        return 1;
    }

    method init(%args) {
        $self->log('Initializing new distribution...');

        # Load from existing META.json if available and args are missing
        if ( defined $config ) {
            $args{name}    //= $config->{name};
            $args{version} //= $config->{version};

            # Add other fields as needed
        }

        # Basic Identity
        my $pkg = $args{name} // $self->prompt('Package Name (e.g. My::Dist)') // die 'Package name required';
        $self->log( 'Minting %s', $self->name($pkg) =~ s[-][::]rg );

        # Create subdirectory if we are not already in it
        # If META.json exists in current path, assume we are re-minting in place.
        my $target_dir = $self->name;
        if ( !$path->child('META.json')->exists && $path->basename ne $target_dir ) {
            $path = $path->child($target_dir);
            $path->mkdir;
        }
        my $ver = $args{version} // $self->prompt("Initial Version [v0.0.1]") // 'v0.0.1';
        $self->version($ver);
        my $desc_default = defined $config ? $config->{description} : undef;
        my $desc         = $args{description} // $self->prompt( "Short Description" . ( $desc_default ? " [$desc_default]" : "" ) ) // $desc_default;
        $self->abstract($desc)    if $desc;
        $self->description($desc) if $desc;    # Also set description

        # License Selection
        my $lic_default = defined $config && $config->{license} ? $config->{license}[0] : 'artistic_2';
        my $lic         = $args{license} // $self->prompt("License (artistic_2, perl_5, mit) [$lic_default]") // $lic_default;
        $config->{license} = [$lic];

        # 3. Features (Populate config for Plugins)
        my $use_gh = $args{github_actions} // $self->prompt("Generate GitHub Actions CI? [y/N]") // 'n';
        if ( $use_gh =~ /^y/i || $use_gh eq '1' ) {

            # Add the plugin to the config so it loads next time
            push @{ $config->{x_plugins} }, 'GitHubActions';

            # Copy workflows from eg/.github to .github
            # Assuming 'eg' is in the distribution root where mii is running from?
            # Or we should look for it relative to where mii.pl is?
            # For now, let's try to find it relative to INC or just assume we have the content inline or in share.
            # But the prompt says "workflows I just copied to eg/.github/".
            # I'll try to locate 'eg/.github' relative to current dir or ../eg if in script.
            my $eg_github = Path::Tiny::path('eg/.github');
            if ( !$eg_github->exists ) {
                $eg_github = Path::Tiny::path('../eg/.github');    # Try parent
            }
            if ( $eg_github->exists ) {
                my $target_github = $path->child('.github');
                $target_github->mkdir;
                $eg_github->visit(
                    sub {
                        my ( $p, $state ) = @_;
                        return if $p->is_dir;
                        my $rel  = $p->relative($eg_github);
                        my $dest = $target_github->child($rel);
                        $dest->parent->mkpath;
                        $p->copy($dest);
                    },
                    { recurse => 1 }
                );
                $self->log("Copied GitHub Actions workflows from $eg_github");
            }
            else {
                $self->log("Warning: Could not find eg/.github to copy workflows from.");
            }

# Manually load it now for this run (though we just copied files manually above, maybe we don't need the plugin object active right now if we just did the work?)
# But keeping consistency
            builtin::load_module "App::mii::Plugin::GitHubActions";
            push @plugins, App::mii::Plugin::GitHubActions->new;
        }

        # Scaffolding
        $self->git( 'init', $path );
        $path->child($_)->mkdir for qw[t lib script eg share];
        $self->spew_package( $self->distribution );
        $self->spew_gitignore;
        $self->git( 'add', '.gitignore' );

        # Core Files
        $self->spew_meta;    # Saves x_plugins to META.json
        $self->spew_meta_yml;
        $self->spew_changes;
        $self->spew_cpanfile;
        $self->spew_license;
        $self->spew_builder;
        $self->spew_build_pl;
        $self->spew_compile_t;
        $self->spew_tidyall_rc;

        # Trigger Plugin Init
        $self->trigger('after_init');

        # Finalize
        $self->gather_files;    # Generates MANIFEST
        $self->git( 'add', '.' );
        say "Initialized $pkg in $path";
    }

    method run( $exe, @args ) {
        $self->log( join ' ', '$', $exe, @args );
        my ( $stdout, $stderr, $exit ) = Capture::Tiny::capture { system $exe, @args; };
    }

    method tee( $exe, @args ) {
        $self->log( join ' ', '$', $exe, @args );
        my ( $stdout, $stderr, $exit ) = Capture::Tiny::tee { system $exe, @args; };
    }

    method git(@args) {
        $self->run( 'git', @args );
    }

    method whoami() {
        my ($me) = $self->git(qw[config user.name]);
        my ($at) = $self->git(qw[config user.email]);
        $me // return ();
        chomp $me;
        chomp $at if $at;
        $me . ( $at ? qq[ <$at>] : '' );
    }

    method contributors () {
        my ( undef, undef, $commits ) = $self->git( 'log', '--head' );
        !$commits or return ();
        my ( $stdout, $stderr, $exit ) = $self->git( 'shortlog', '-se' );
        !$exit or return ();
        my %uniq;
        my @authors = map {m[^.+ <(.+?)>$]} @{ $self->author };
        for my $pal ( split /\n/, $stdout ) {
            $pal =~ s[^\s+\d+\s+][];
            my ($email) = $pal =~ m[^.+ <(.+?)>$];
            $uniq{$email} //= $pal unless grep { $email eq $_ } @authors;
        }
        sort values(%uniq);
    }

    # Utils
    sub _list_and (@list) {
        return shift @list if scalar @list == 1;
        join( ', ', @list[ 0 .. -1 ] ) . ' and ' . $list[-1];
    }

    method run_hook( $phase, @args ) {
        return unless defined $config->{hooks} && defined $config->{hooks}{$phase};
        $self->log("Running hook: $phase");
        my $cmd = $config->{hooks}{$phase};
        if ( ref $cmd eq 'ARRAY' ) {
            system( @$cmd, @args ) == 0 or die "Hook $phase failed\n";
        }
        else {
            system( $cmd, @args ) == 0 or die "Hook $phase failed\n";
        }
    }

    method load_plugins() {
        my $list = $config->{x_plugins} // [];
        for my $entry (@$list) {
            my $pkg = $entry;
            $pkg = "App::mii::Plugin::$pkg" unless $pkg =~ s/^\+//;
            try {
                builtin::load_module $pkg;
                push @plugins, $pkg->new();    # Plugins must have a new() constructor
            }
            catch ($err) {
                $self->log( 'Failed to load plugin %s: %s', $pkg, $err );
            }
        }
    }

    # Calls the method named $event on all plugins that support it.
    # Passes $self (the app) and any args.
    method trigger( $event, @args ) {
        for my $plugin (@plugins) {
            if ( $plugin->can($event) ) {
                $plugin->$event( $self, @args );
            }
        }
    }

    method check_git_clean() {
        my ($stat) = $self->git( 'status', '--porcelain' );
        if ($stat) {
            $self->log('WARNING before next release: Working directory is dirty.');
            $self->log($stat);
            $self->log('I suggest you commit your changes first.');
        }
    }
};
#
1;
__END__
=encoding utf-8

=head1 NAME

App::mii - Minimalist Dist Builder

=head1 SYNOPSIS

    use App::mii;
    App::mii->new->dist;

=head1 DESCRIPTION

App::mii is a minimalist distribution builder for Perl. It provides methods to initialize, build, test, and release
Perl distributions.

=head1 METHODS

=head2 init

    $mii->init( name => 'My::Dist', version => 'v0.0.1' );

Initializes a new distribution skeleton in a subdirectory named after the package.

=head2 dist

    $mii->dist( verbose => 1 );

Builds a tarball of the distribution.

=head2 disttest

    $mii->disttest( verbose => 1 );

Builds the distribution and runs tests using cpanm.

=head2 release

    $mii->release( pause => 1 );

Builds, tests, and optionally uploads the distribution to PAUSE. If the C<x_private> variable is set to a true value in
F<META.json>, this method will refuse to release the distribution.

=head1 CUSTOM METADATA

C<App::mii> supports several custom metadata fields in F<META.json>:

=over

=item x_private

=item x_no_upload

If set to a true value, C<mii> will refuse to upload the distribution to CPAN.

=item x_ignore

An array of glob patterns to ignore when gathering files for the distribution.

=item x_readme_from

The file to use as the source for F<README.md>. Defaults to the main module or pod file.

=item x_version_from

The file to use as the source for the distribution version. Defaults to the main module.

=item x_pause_from

The path to a F<.pause> configuration file. Defaults to F<~/.pause>.

=item x_plugins

An array of plugins to load.

=back

=head1 AUTHOR

Sanko Robinson E<lt>sanko@cpan.orgE<gt>

=cut

