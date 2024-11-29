#!perl
# This is mii2
use v5.38;
use feature 'class';
no warnings 'experimental::class', 'experimental::builtin';
use Carp           qw[];
use Template::Tiny qw[];       # not in CORE
use Pod::Usage     qw[];
use Capture::Tiny  qw[];       # not in CORE
use Software::License;         # not in CORE
use Software::LicenseUtils;    # not in CORE
use Module::Metadata qw[];
use Module::CPANfile qw[];
#
use App::mii::Markdown;
#
class App::mii v2.0.0 {
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
    #
    method abstract( $v //= () )    { $config->{abstract} = $v if defined $v; $self->config->{abstract}; }
    method description( $v //= () ) { $config->{description} = $v if defined $v; $self->config->{description} }
    method version( $v //= () )     { $config->{version} = $v if defined $v; version::parse( 'version', $self->config->{version} ); }
    method name ( $v //= () )       { $config->{name} = $v =~ s[::][-]gr if defined $v; $self->config->{name} }
    method distribution ()          { $config->{name} =~ s[-][::]gr }
    method author ()                { $config->{author} //= [ $self->whoami ] }

    method license ( $v //= () ) {
        if ( defined $v && ref $v eq 'ARRAY' ) {
            $config->{license} = $v;
        }
        map {
            my ($pkg) = Software::LicenseUtils->guess_license_from_meta_key( $_, 2 );
            defined $pkg ? $pkg->new( { holder => _list_and( @{ $self->author } ) } ) :
                $self->log( 'Software::License has no knowledge of "%s"', $_ ) &&
                ()
        } @{ $config->{license} };
    }
    #
    method log ( $msg, @etc ) { say @etc ? sprintf $msg, @etc : $msg; }

    method prompt( $msg, @etc ) {
        $msg .= '> ';
        print @etc ? sprintf $msg, @etc : $msg;
        my $ret = <STDIN>;
        chomp $ret;
        $ret;
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
        warn $meta->stringify;
        if ( $meta->exists ) {
            $config = CPAN::Meta->load_file($meta);

            #~ $config = decode_json $meta->slurp_utf8;
        }
        else {
            #~ my $distmeta_struct = {
            #~ name => $self->distribution,
            #~ version =>
            #~ $self->prompt('Version [v1.0.0]') // 'v1.0.0'};
            #~ use Data::Dump;
            #~ ddx $distmeta_struct;
            #~ $config = CPAN::Meta->new($distmeta_struct);
        }

        #~ $path = $path->child( $self->name ) if defined $self->name;
        #~ elsif ( defined $package ) {
        #~ $self->name($package);
        #~ }
        #~ elsif ( $package = $self->prompt('I need a package name or something') ) {
        #~ $self->name($package) if defined $package;
        #~ }
    }

    # Pull list of files from git
    method gather_files() {
        my ($msg) = $self->git('ls-files');
        $self->spew_meta;
        $self->spew_cpanfile;
        $self->spew_license;
        $self->spew_changes;
        map { Path::Tiny::path($_)->relative } split /\R+/, $msg;
    }

    method generate_meta() {
        state $meta;
        return $meta if defined $meta;
        my $stable = !$self->version->is_alpha;
        exit !$self->log( 'No modules found in ' . $path->child('lib') ) unless $path->child('lib')->children;
        my $provides = $stable ? Module::Metadata->provides( dir => $path->child('lib')->canonpath, version => 2 ) : {};
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
                    perl                     => 'v5.38.0'
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
            abstract       => $self->abstract,
            author         => $self->author,
            dynamic_config => $config->{dynamic_config} // 1,                                         # lies
            generated_by   => 'App::mii ' . $App::mii::VERSION,
            license        => [ map { $_->meta_name } $self->license ],
            'meta-spec'    => { version => 2, url => 'https://metacpan.org/pod/CPAN::Meta::Spec' },
            name           => $self->name,
            release_status => $stable ? 'stable' : 'unstable',                                        # TODO: stable, testing, unstable
            version        => $self->version->stringify,

            # https://metacpan.org/pod/CPAN::Meta::Spec#OPTIONAL-FIELDS
            description => $config->{description} // '',
            keywords    => $config->{keywords}    // [],
            no_index    => $config->{no_index}    // { file => [], directory => [], package => [], namespace => [] },
            ( defined $config->{optional_features} ? ( optional_features => $config->{optional_features} ) : () ),
            prereqs   => \%prereqs,
            provides  => $provides,                                                                   # blank unless stable
            resources => { ( defined $config->{resources} ? %{ $config->{resources} } : () ), license => [ map { $_->url } $self->license ] },
            #
            sub {
                my @contributors = $self->contributors;
                scalar @contributors ? ( x_contributors => \@contributors ) : ();
            }
                ->()
        };
    }

    method spew_meta ( $out //= $path->child('META.json') ) {    # I could use CPAN::Meta but...
        $out = $path->child($out) unless builtin::blessed $out;
        state $json //= JSON::PP->new->utf8->pretty->indent->core_bools->canonical->allow_nonref;
        $out->spew_utf8( $json->encode( $self->generate_meta ) ) && return $out;
    }

    method spew_changes( $out //= $path->child('Changes') ) {
        warn 'TODO: I need to dump a basic changelog if it does not exist';
        warn 'TODO: If it exists, I need to update the latest section with the current version';
    }

    method spew_cpanfile( $out //= $path->child('cpanfile') ) {
        $out = $path->child($out) unless builtin::blessed $out;
        my $cpanfile = Module::CPANfile->from_prereqs( $self->generate_meta->{prereqs} );
        $cpanfile->save($out) && return $out;
    }

    method spew_license( $out //= $path->child('LICENSE') ) {
        $out = $path->child($out) unless builtin::blessed $out;
        $out->spew_utf8( join( '-' x 20 . "\n", map { $_->fulltext } $self->license ) ) && return $out;
    }

    method spew_build_pl( $out //= $path->child('Build.PL') ) {
        $out = $path->child($out) unless builtin::blessed $out;
        my $dist = $self->distribution;
        $out->touchpath;
        $out->spew_utf8( <<END ) && return $out; }
use v5.38;
use lib 'builder';
use ${dist}::Builder;
${dist}::Builder->new->Build_PL();
END

    method spew_builder( $out //= $self->package2path( $self->distribution . '::Builder', 'builder' ) ) {
        $out = $path->child($out) unless builtin::blessed $out;
        my $dist = $self->distribution;
        $out->touchpath;
        $out->spew_utf8( <<'END' =~ s[\{\{dist}}][$dist]rg ) && return $out; }
# Based on Module::Build::Tiny which is copyright (c) 2011 by Leon Timmermans, David Golden.
# Module::Build::Tiny is free software; you can redistribute it and/or modify it under
# the same terms as the Perl 5 programming language system itself.
use v5.38;
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
    field $verbose : param(v)    //= 0;
    field $dry_run : param       //= 0;
    field $pureperl : param      //= 0;
    field $jobs : param          //= 1;
    field $destdir : param       //= '';
    field $prefix : param        //= '';
    #
    ADJUST {
        -e 'META.json' or die "No META information provided\n";
    }
    method write_file( $filename, $content ) { path($filename)->spew_utf8($content) or die "Could not open $filename: $!\n" }
    method read_file ($filename)             { path($filename)->slurp_utf8          or die "Could not open $filename: $!\n" }

    method step_build() {
        for my $pl_file ( find( qr/\.PL$/, 'lib' ) ) {
            ( my $pm = $pl_file ) =~ s/\.PL$//;
            system $^X, $pl_file, $pm and die "$pl_file returned $?\n";
        }
        my %modules       = map { $_ => catfile( 'blib', $_ ) } find( qr/\.pm$/,  'lib' );
        my %docs          = map { $_ => catfile( 'blib', $_ ) } find( qr/\.pod$/, 'lib' );
        my %scripts       = map { $_ => catfile( 'blib', $_ ) } find( qr/(?:)/,   'script' );
        my %sdocs         = map { $_ => delete $scripts{$_} } grep {/.pod$/} keys %scripts;
        my %dist_shared   = map { $_ => catfile( qw[blib lib auto share dist],   $meta->name, abs2rel( $_, 'share' ) ) } find( qr/(?:)/, 'share' );
        my %module_shared = map { $_ => catfile( qw[blib lib auto share module], abs2rel( $_, 'module-share' ) ) } find( qr/(?:)/, 'module-share' );
        pm_to_blib( { %modules, %docs, %scripts, %dist_shared, %module_shared }, catdir(qw[blib lib auto]) );
        make_executable($_) for values %scripts;
        !mkpath( catdir(qw[blib arch]), $verbose );
    }
    method step_clean() { rmtree( $_, $verbose ) for qw[blib temp]; 0 }

    method step_install() {
        $self->step_build() unless -d 'blib';
        install( $install_paths->install_map, $verbose, $dry_run, $uninst );
        return 0;
    }
    method step_realclean () { rmtree( $_, $verbose ) for qw[blib temp Build _build_params MYMETA.yml MYMETA.json]; 0 }

    method step_test() {
        $self->step_build() unless -d 'blib';
        require TAP::Harness::Env;
        my %test_args = (
            ( verbosity => $verbose ),
            ( jobs  => $jobs ),
            ( color => -t STDOUT ),
            lib => [ map { rel2abs( catdir( 'blib', $_ ) ) } qw[arch lib] ],
        );
        TAP::Harness::Env->create( \%test_args )->runtests( sort +find( qr/\.t$/, 't' ) )->has_errors;
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
%s->new( @ARGV && $ARGV[0] =~ /\A\w+\z/ ? ( action => shift @ARGV ) : (),
    map { /^--/ ? ( shift(@ARGV) =~ s[^--][]r => 1 ) : /^-/ ? ( shift(@ARGV) =~ s[^-][]r => shift @ARGV ) : () } @ARGV )->Build();

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

    sub find {
        my ( $pattern, $dir ) = @_;
        my @ret;
        File::Find::find( sub { push @ret, $File::Find::name if /$pattern/ && -f }, $dir ) if -d $dir;
        return @ret;
    }
    };
1;
END

    method spew_gitignore( $out //= $path->child('.gitignore') ) {
        $out = $path->child($out) unless builtin::blessed $out;
        my $dist = $self->name;
        $out->spew_utf8( <<END) && return $out; }
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
        $out->spew_utf8( <<END) && return $out; }
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
        $out->spew_utf8( <<END ) && return $out;
use v5.38;
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
        my $abstract    = $self->abstract;
        my $description = $self->description;
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
        $file->spew_utf8( <<END) && $file }
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
        if ( defined $self->config->{x_readme_from} ) {
            $readme_src = $self->path->child( $self->config->{x_readme_from} );
        }
        if ( !( defined $readme_src && $readme_src->exists ) ) {
            my $pm  = $self->package2path( $self->distribution );
            my $pod = $pm->sibling( $pm->basename('.pm') . '.pod' );
            $readme_src = $pod->exists ? $pod : $pm;
        }
        $out->spew_utf8( App::mii::Markdown->new->parse_from_file( $readme_src->canonpath )->as_markdown ) && return $out;
    }

    method spew_tar_gz( $out //= Path::Tiny::path( $self->name . '-' . $self->version . '.tar.gz' )->absolute ) {
        $out = $path->child($out) unless builtin::blessed $out;
        state $dist;

        #~ return $dist if defined $dist;
        require Archive::Tar;
        require List::Util;
        my $arch    = Archive::Tar->new;
        my $tar_dir = Path::Tiny->new( $self->name . '-' . $self->version );

        # Broken on Windows?
        $arch->add_data( $tar_dir->child($_)->stringify, $_->slurp_raw ) for grep {
            my $re = $_;
            not List::Util::any { $_ =~ /$re/ } @{ $config->{'x_ignore'} }
        } $self->gather_files;
        $_->mode( $_->mode & ~022 ) for $arch->get_files;
        $arch->write( $out->stringify, &Archive::Tar::COMPRESS_GZIP() );
        $out->size ? $dist = $out : ();
    }

    method dist( $verbose //= 1 ) {

        #~ TODO: $self->run('tidyall', '-a');
        #~ TODO: update version number in Changelog, Meta.json, etc.
        #~ eval 'use Test::Spellunker; 1' && Test::Spellunker::all_pod_files_spelling_ok();
        # TODO: Also spell check changelog
        $self->git( 'add', $self->spew_readme_md );
        my $dev_tests  = $path->child( 't', 'dev' );
        my $spelling_t = eval { require Test::Spellunker } ? $dev_tests->child('spellunker.t')->touchpath->spew_utf8(<<'') : ();
use Test::Spellunker;
all_pod_files_spelling_ok();

        my $pod_t = eval { require Test::Pod } ? $dev_tests->child('pod.t')->touchpath->spew_utf8(<<'') : ();
use Test2::V0;
use Test::Pod;
all_pod_files_ok();
done_testing;

        $self->test($verbose);
        $dev_tests->remove_tree( { safe => 0 } );
        $self->spew_tar_gz;
    }

    method test( $verbose //= 0 ) {
        $self->tee( $^X, 'Build.PL' ) unless -d 'blib';
        $self->tee( $^X, 'Build', 'test' );
    }

    method disttest( $verbose //= 0 ) {

        #~ TODO: $self->run('tidyall', '-a');
        #~ TODO: update version number in Changelog, Meta.json, etc.
        #~ eval 'use Test::Spellunker; 1' && Test::Spellunker::all_pod_files_spelling_ok();
        # TODO: Also spell check changelog
        $self->git( 'add', $self->spew_readme_md );
        #
        my $dist = $self->spew_tar_gz;
        my ( $stdout, $stderr, $exit ) = $self->tee( 'cpanm', ( $verbose ? '--verbose' : () ), '--test-only', $dist );
        $exit ? () : $dist;
    }

    method release( $ver //= $self->version, $upload //= 0 ) {
        ...;
    }

    method init( $pkg //= $self->name // $self->prompt('Package name'), $ver //= v1.0.0 ) {
        $self->name($pkg);
        $self->version($ver);

        #~ $path = $path->child( $self->name );
        $config->{license} //= ['artistic_2'];
        $self->git( 'init', $path );
        {
            $path->child($_)->mkdir for qw[t lib script eg share];
            $self->spew_package( $self->distribution );
            $self->spew_meta;
            $self->spew_cpanfile;
            $self->spew_changes;
            $self->spew_license;
            $self->spew_builder;
            $self->spew_build_pl;
            $self->spew_compile_t;
            $self->spew_gitignore;
            $self->git( 'add', '.gitignore' );
            $self->spew_tidyall_rc;
            #
            $self->package2path( $self->distribution );    #->touch;
        }
        $_->touchpath for map { $path->child($_) } qw[t lib script eg share];
        $self->git( 'add', '.' );
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
};
#
1
