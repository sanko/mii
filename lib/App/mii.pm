use v5.38;
use feature 'class';
no warnings 'experimental::class', 'experimental::builtin';
use version        qw[];
use Carp           qw[];
use Template::Tiny qw[];       # not in CORE
use JSON::PP       qw[];       # not in CORE
use Path::Tiny     qw[];       # not in CORE
use Pod::Usage     qw[];
use Capture::Tiny  qw[];       # not in CORE
use Software::License;         # not in CORE
use Software::LicenseUtils;    # not in CORE
use Module::Metadata qw[];
use Module::CPANfile qw[];
#
class App::mii v0.0.1 {
    method log ( $msg, @etc ) { say @etc ? sprintf $msg, @etc : $msg; }
    field $author;
    field $distribution;    # Required
    field $license;
    field $vcs;
    field $version;
    field $path = Path::Tiny::path('.')->realpath;
    field $config;
    my $json = JSON::PP->new->utf8->space_after;
    ADJUST {
        $config       = $self->slurp_config;
        $author       = $config->{author};
        $distribution = $config->{distribution};
        $license      = $config->{license};
        $vcs          = $config->{vcs};
        $version      = $config->{version};
        if ( !builtin::blessed $vcs ) {
            my $pkg = {
                git    => 'App::mii::VCS::Git',
                hg     => 'App::mii::VCS::Mercurial',
                brz    => 'App::mii::VCS::Breezy',
                fossil => 'App::mii::VCS::Fossil',
                svn    => 'App::mii::VCS::Subversion'
            }->{$vcs};
            $self->log(qq[Unknown VCS type "$vcs"; falling back to App::mii::VCS::Tar]) unless $pkg;
            $vcs = ( $pkg // 'App::mii::VCS::Tar' )->new();
        }
        $author //= $vcs->whoami // exit $self->log(q[Unable to guess author's name. Help me out and use --author]);
        my $info = Module::Metadata->new_from_module( $distribution, inc => [ $path->child('lib')->stringify ] );
        $version = $info->version;
        $license = [$license] if ref $license ne 'ARRAY';
        $license = ['artistic_2'] unless scalar @$license;
        if ( grep { !builtin::blessed $license } @$license ) {
            $license = [
                map {
                    my ($pkg) = Software::LicenseUtils->guess_license_from_meta_key($_);
                    exit $self->log( qq[Software::License has no knowledge of "%s"], $_ ) unless $pkg;
                    $pkg
                } @$license
            ];
            $license = [ map { $_->new( { holder => $author, Program => $distribution } ) } @$license ];
        }
    };

    method dist() {
        eval 'use Test::Spellunker; 1' && Test::Spellunker::all_pod_files_spelling_ok();
        $path->child('META.json')->spew_utf8( $json->utf8->pretty(1)->allow_blessed(1)->canonical->encode( $self->generate_meta() ) );
        $vcs->add_file( $path->child('META.json') );
        {
            my @dir        = split /::/, $distribution;
            my $file       = pop @dir;
            my $readme_src = $path->child( $config->{readme_from} // ( 'lib', @dir, $file . '.pod' ) );
            $readme_src = $path->child( 'lib', $distribution . '.pm' ) unless $readme_src->exists;
            $path->child('README.md')->spew_utf8( App::mii::Markdown->new->parse_from_file( $readme_src->canonpath )->as_markdown )
                if $readme_src->exists;
        }
        {
            #~ TODO: copy all files to tempdir, update version number in Changelog, run Build.PL, etc.
            #~ $self->run( $^X, 'Build.PL' );
            #~ $self->run( $^X, './Build' );
            #~ $self->run( $^X, './Build test' );
            require Archive::Tar;
            my $arch = Archive::Tar->new;
            $arch->add_files( grep { !/mii\.conf/ } $self->gather_files );
            $_->mode( $_->mode & ~022 ) for $arch->get_files;
            my $dist = sprintf '%s::%s.tar.gz', $distribution, $version;
            $dist =~ s[::][-]g;
            $dist = Path::Tiny::path($dist)->canonpath;
            $arch->write( $dist, &Archive::Tar::COMPRESS_GZIP() );
            return -s $dist;

            #~ return $file;
        }
    }

    method run ( $cmd, @args ) {
        system $cmd, @args;
    }

    method usage ( $msg, $sections //= () ) {
        Pod::Usage::pod2usage( -message => qq[$msg\n], -verbose => 99, -sections => $sections );
    }

    method generate_meta() {
        my $cpanfile = Module::CPANfile->load;
        my $stable   = !$version->is_alpha;
        my $provides = $stable ? Module::Metadata->provides( dir => $path->child('lib')->canonpath, version => 2 ) : {};
        $_->{file} =~ s[\\+][/]g for values %$provides;
        {
            # https://metacpan.org/pod/CPAN::Meta::Spec#REQUIRED-FIELDS
            abstract       => $config->{abstract},
            author         => $author,
            dynamic_config => 1,
            generated_by   => sprintf( 'App::mii %s', $App::mii::VERSION ),
            license        => [ map { $_->meta_name } @$license ],
            'meta-spec'    => { version => 2, url => 'https://metacpan.org/pod/CPAN::Meta::Spec' },
            name           => sub { join '-', split /::/, $distribution }
                ->(),
            release_status => $stable ? 'stable' : 'unstable',    # TODO: stable, testing, unstable
            version        => $version->stringify,

            # https://metacpan.org/pod/CPAN::Meta::Spec#OPTIONAL-FIELDS
            ( defined $config->{description} ? ( description => $config->{description} ) : () ),
            ( defined $config->{keywords}    ? ( keywords    => $config->{keywords} )    : () ),
            no_index => { file => [], directory => [], package => [], namespace => [] },
            ( defined $config->{features} ? ( optional_features => $config->{features} ) : () ),
            prereqs   => $cpanfile->prereq_specs,
            provides  => $provides,                               # blank unless stable
            resources => { ( defined $config->{resources} ? %{ $config->{resources} } : () ), license => [ map { $_->url } @$license ] }
        };
    }

    method slurp_config() {
        my $dot_conf = Path::Tiny::path('.')->child('mii.conf');
        exit $self->log('mii.conf not found; to create a new project, try `mii help mint`') unless $dot_conf->is_file;
        $json->decode( $dot_conf->slurp_utf8() );
    }
    method gather_files() { $vcs->gather_files }
};

class App::mii::Mint::Base {
    field $author : param //= ();    # We'll ask VSC as a last resort
    field $distribution : param;     # Required
    field $license : param //= ['artistic_2'];
    field $vcs : param     //= 'git';
    field $version : param //= 'v0.0.1';
    field $path = './' . join '-', split /::/, $distribution;
    ADJUST {
        if ( !builtin::blessed $vcs ) {
            my $pkg = {
                git    => 'App::mii::VCS::Git',
                hg     => 'App::mii::VCS::Mercurial',
                brz    => 'App::mii::VCS::Breezy',
                fossil => 'App::mii::VCS::Fossil',
                svn    => 'App::mii::VCS::Subversion'
            }->{$vcs};
            $self->log(qq[Unknown VCS type "$vcs"; falling back to App::mii::VCS::Tar]) unless $pkg;
            $vcs = ( $pkg // 'App::mii::VCS::Tar' )->new();
        }
        $author //= $vcs->whoami // exit $self->log(q[Unable to guess author's name. Help me out and use --author]);
        $license = [$license] if ref $license ne 'ARRAY';
        $license = ['artistic_2'] unless scalar @$license;
        if ( grep { !builtin::blessed $license } @$license ) {
            $license = [
                map {
                    my ($pkg) = Software::LicenseUtils->guess_license_from_meta_key($_);
                    exit $self->log( qq[Software::License has no knowledge of "%s"], $_ ) unless $pkg;
                    $pkg
                } @$license
            ];
            $license = [ map { $_->new( { holder => $author, Program => $distribution } ) } @$license ];
        }
        if ( !builtin::blessed $path ) {
            $path = Path::Tiny::path($path)->realpath;
        }
    }
    method license() {$license}
    method vcs()     {$vcs}

    method config() {
        +{ author => $author, distribution => $distribution, license => [ map { $_->meta_name } @$license ], vcs => $vcs->name };
    }
    method slurp_config()     { }
    method log ( $msg, @etc ) { say @etc ? sprintf $msg, @etc : $msg; }

    method mint() {
        {
            my @dir  = split /::/, $distribution;
            my $file = pop @dir;
            $path->child( 'lib', @dir )->mkdir;
            my $license_blurb = qq[=head1 LICENSE\n\n];
            if ( @$license > 1 ) {
                $license_blurb .= sprintf "%s is covered by %d licenses.\n\nSee the L<LICENSE> file for full text.\n\n=over\n\n", $distribution,
                    scalar @$license;
                for my $l (@$license) {
                    $license_blurb .= sprintf "=item * %s\n\n", ucfirst $l->name;
                    my $chunk       = $l->notice;
                    my $license_url = $l->url;
                    $license_blurb .= $chunk;
                    $license_blurb .= $license_url ? qq[\nSee L<$license_url>.\n\n] : '';
                }
                $license_blurb .= "=back";
            }
            else {
                my $chunk       = $license->[0]->notice;
                my $license_url = $license->[0]->url;
                $license_blurb .= $chunk;
                $license_blurb .= $license_url ? qq[\nSee L<$license_url>.] : '';
            }

            # TODO: Allow this default .pm to be a template from userdir
            $path->child( 'lib', @dir, $file . '.pm' )->spew_utf8(<<PM);
package $distribution $version {
    use v5.38;
    sub greet (\$whom) { "Hello, \$whom" }
};
1;

=encoding utf-8

=head1 NAME

$distribution - Spankin' New Code

=head1 SYNOPSIS

    use $distribution;

=head1 DESCRIPTION

$distribution is brand new, baby!

$license_blurb

=head1 AUTHOR

$author

=begin stopwords


=end stopwords

=cut

PM
        }
        $path->child($_)->mkdir for qw[builder eg t];
        $path->child( 't', '00_compile.t' )->spew_utf8(<<T);
use Test2::V0;
use lib './lib', '../lib';
use $distribution;
#
diag \$${distribution}::VERSION;
is ${distribution}::greet('World'), 'Hello, World', 'proper greeting';
#
done_testing;
T
        $path->child('LICENSE')->spew_utf8( join( '-' x 20 . "\n", map { $_->fulltext } @$license ) );
        $path->child('Changes')->spew_utf8( <<CHANGELOG );    # %v is non-standard and returns version number
# Changelog for $distribution

All notable changes to this project will be documented in this file.

## [{{NEXT:%v}}] - {{NEXT:%Y-%m-%d}}

### Added

- This CHANGELOG file to hopefully serve as an evolving example of a
  standardized open source project CHANGELOG.
- See https://keepachangelog.com/en/1.1.0/

CHANGELOG

        # TODO: cpanfile
        $path->child('cpanfile')->spew_utf8(<<'CPAN');
requires perl => v5.38.0;

on configure =>sub{};
on build=>sub{};
on test => sub {
    requires 'Test2::V0';
};
on configure=>sub{};
on runtime=>sub{};
CPAN
        $path->child('Build.PL')->spew_utf8(<<'BUILD_PL');
#!perl
use lib '.';
use builder::mbt;
builder::mbt::Build_PL();
BUILD_PL
        $path->child( 'builder', 'mbt.pm' )->touchpath->spew_utf8( <<'BUILDER' );
package builder::mbt v0.0.1 {    # inspired by Module::Build::Tiny 0.047
    use v5.26;
    use CPAN::Meta;
    use ExtUtils::Config 0.003;
    use ExtUtils::Helpers 0.020 qw/make_executable split_like_shell detildefy/;
    use ExtUtils::Install qw/pm_to_blib install/;
    use ExtUtils::InstallPaths 0.002;
    use File::Spec::Functions qw/catfile catdir rel2abs abs2rel/;
    use Getopt::Long 2.36     qw/GetOptionsFromArray/;
    use JSON::Tiny            qw[encode_json decode_json];          # Not in CORE
    use Path::Tiny            qw[path];                             # Not in CORE
    my $cwd = path('.')->realpath;

    sub get_meta {
        state $metafile //= path('META.json');
        exit say "No META information provided\n" unless $metafile->is_file;
        return CPAN::Meta->load_file( $metafile->realpath );
    }

    sub find {
        my ( $pattern, $dir ) = @_;

        #~ $dir = path($dir) unless $dir->isa('Path::Tiny');
        sort values %{
            $dir->visit(
                sub {
                    my ( $path, $state ) = @_;
                    $state->{$path} = $path if $path->is_file && $path =~ $pattern;
                },
                { recurse => 1 }
            )
        };
    }
    my %actions;
    %actions = (
        build => sub {
            my %opt     = @_;
            my %modules = map { $_->relative => $cwd->child( 'blib', $_->relative )->relative } find( qr/\.pm$/,  $cwd->child('lib') );
            my %docs    = map { $_->relative => $cwd->child( 'blib', $_->relative )->relative } find( qr/\.pod$/, $cwd->child('lib') );
            my %scripts = map { $_->relative => $cwd->child( 'blib', $_->relative )->relative } find( qr/(?:)/,   $cwd->child('script') );
            my %sdocs   = map { $_           => delete $scripts{$_} } grep {/.pod$/} keys %scripts;
            my %shared  = map { $_->relative => $cwd->child( qw[blib lib auto share dist], $opt{meta}->name )->relative }
                find( qr/(?:)/, $cwd->child('share') );
            pm_to_blib( { %modules, %docs, %scripts, %shared }, $cwd->child(qw[blib lib auto]) );
            make_executable($_) for values %scripts;
            $cwd->child(qw[blib arch])->mkdir( { verbose => $opt{verbose} } );
            return 0;
        },
        test => sub {
            my %opt = @_;
            $actions{build}->(%opt) if not -d 'blib';
            require TAP::Harness::Env;
            TAP::Harness::Env->create(
                {   verbosity => $opt{verbose},
                    jobs      => $opt{jobs} // 1,
                    color     => !!-t STDOUT,
                    lib       => [ map { $cwd->child( 'blib', $_ )->canonpath } qw[arch lib] ]
                }
            )->runtests( map { $_->relative->stringify } find( qr/\.t$/, $cwd->child('t') ) )->has_errors;
        },
        install => sub {
            my %opt = @_;
            $actions{build}->(%opt) if not -d 'blib';
            install( $opt{install_paths}->install_map, @opt{qw[verbose dry_run uninst]} );
            return 0;
        },
        clean => sub {
            my %opt = @_;
            path($_)->remove_tree( { verbose => $opt{verbose} } ) for qw[blib temp Build _build_params MYMETA.json];
            return 0;
        },
    );

    sub Build {
        my $action = @ARGV && $ARGV[0] =~ /\A\w+\z/ ? shift @ARGV : 'build';
        $actions{$action} // exit say "No such action: $action";
        my $build_params = path('_build_params');
        my ( $env, $bargv ) = $build_params->is_file ? @{ decode_json( $build_params->slurp_utf8 ) } : ();
        GetOptionsFromArray(
            $_,
            \my %opt,
            qw/install_base=s install_path=s% installdirs=s destdir=s prefix=s config=s% uninst:1 verbose:1 dry_run:1 pureperl-only:1 create_packlist=i jobs=i/
        ) for grep {defined} $env, $bargv, \@ARGV;
        $_ = detildefy($_) for grep {defined} @opt{qw[install_base destdir prefix]}, values %{ $opt{install_path} };
        @opt{qw[config meta]} = ( ExtUtils::Config->new( $opt{config} ), get_meta() );
        exit $actions{$action}->( %opt, install_paths => ExtUtils::InstallPaths->new( %opt, dist_name => $opt{meta}->name ) );
    }

    sub Build_PL {
        my $meta = get_meta();
        printf "Creating new 'Build' script for '%s' version '%s'\n", $meta->name, $meta->version;
        $cwd->child('Build')->spew( sprintf "#!%s\nuse lib '%s', '.';\nuse %s;\n%s::Build();\n", $^X, $cwd->canonpath, __PACKAGE__, __PACKAGE__ );
        make_executable('Build');
        my @env = defined $ENV{PERL_MB_OPT} ? split_like_shell( $ENV{PERL_MB_OPT} ) : ();
        $cwd->child('_build_params')->spew_utf8( encode_json( [ \@env, \@ARGV ] ) );
        $meta->save('MYMETA.json');
    }
}
1;
BUILDER

        # TODO: .github/workflow/*      in ::Git
        # TODO: .github/FUNDING.yaml    in ::Git
        # Finally...
        $path->child('mii.conf')->spew_utf8( JSON::PP->new->utf8->pretty->canonical->encode( $self->config() ) );
        $self->log( 'New project minted in %s', $path->realpath );
        my $cwd = Path::Tiny::path('.')->realpath;
        chdir $path->realpath->stringify;
        $self->log( $vcs->init($path) );
        $self->log( $vcs->add_file('.') );
        chdir $cwd;
    }
}

class App::mii::Mint::Subclass : isa(App::mii::Mint::Base) { }

class App::mii::VCS::Base {
    method whoami() { () }
    method init     ($path) {...}
    method add_file ($path) {...}
    method gather_files()    {...}
    method diff_file ($path) {...}
    method diff_repo()       {...}
    method commit ($message) {...}
    method tag    ($name)    {...}
    method push {...}
}

class App::mii::VCS::Git : isa(App::mii::VCS::Base) {
    method name () {'git'}

    method whoami() {
        my $me = Capture::Tiny::capture_stdout { system qw[git config user.name] };
        my $at = Capture::Tiny::capture_stdout { system qw[git config user.email] };
        $me // return $self->SUPER::whoami();
        chomp $me;
        chomp $at if $at;
        $me . ( $at ? qq[ <$at>] : '' );
    }

    method init ($path) {
        my $msg = Capture::Tiny::capture_stdout { system qw[git init] };
        chomp $msg;
        $msg // return;

        #~ https://github.com/github/gitignore/blob/main/Perl.gitignore
        $path->child('.gitignore')->spew_utf8(<<'GIT_IGNORE');
!Build/
/MYMETA.*
*.o
*.pm.tdy
*.bs
*.old
/*.gz

# Devel::Cover
cover_db/

# Devel::NYTProf
nytprof.out

/.build/

_build/
Build
Build.bat
_build_params

/blib/
/pm_to_blib
GIT_IGNORE
        $msg;
    }

    method add_file ($path) {
        my $msg = Capture::Tiny::capture_stdout { system qw[git add], $path };
        chomp $msg;
        $msg;
    }

    method gather_files() {
        my $msg = Capture::Tiny::capture_stdout { system qw[git ls-files] };
        map { Path::Tiny::path($_)->canonpath } split /\R+/, $msg;
    }
}

class App::mii::VCS::Mercurial : isa(App::mii::VCS::Base) {
    method name () {'hg'}
}

class App::mii::VCS::Breezy : isa(App::mii::VCS::Base) {
    method name () {'brz'}

    # https://www.breezy-vcs.org/doc/en/mini-tutorial/index.html
    method whoami() {
        my $me = Capture::Tiny::capture_stdout { system qw[brz whoami] };
        $me // return $self->SUPER::whoami();
        chomp $me if $me;
        $me;
    }
}

class App::mii::VCS::Fossil : isa(App::mii::VCS::Base) {
    method name () {'fossil'}
}

class App::mii::VCS::Subversion : isa(App::mii::VCS::Base) {
    method name () {'svn'}
}

class App::mii::VCS::Tar : isa(App::mii::VCS::Base) {
    method name () {'tar'}
}

package App::mii::Markdown v0.0.1 {    # based on Pod::Markdown::Github
    use strict;
    use warnings;
    use parent 'Pod::Markdown';

    sub syntax {
        my ( $self, $paragraph ) = @_;
        return ( $paragraph =~ /(\b(sub|my|use|shift)\b|\$self|\=\>|\$_|\@_)/ ) ? 'perl' : '';

        # TODO: add C, C++, D, Fortran, etc. for Affix
    }

    sub _indent_verbatim {
        my ( $self, $paragraph ) = @_;
        $paragraph = $self->SUPER::_indent_verbatim($paragraph);

        # Remove the leading 4 spaces because we'll escape via ```language
        $paragraph = join "\n", map { s/^\s{4}//; $_ } split /\n/, $paragraph;

        # Enclose the paragraph in ``` and specify the language
        return sprintf( "```%s\n%s\n```", $self->syntax($paragraph), $paragraph );
    }
}
1;
