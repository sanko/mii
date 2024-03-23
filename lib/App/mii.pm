use v5.38;
use feature 'class';
no warnings 'experimental::class', 'experimental::builtin';
use version        qw[];
use Carp           qw[];
use Template::Tiny qw[];       # not in CORE
use JSON::Tiny     qw[];       # not in CORE
use Path::Tiny     qw[];       # not in CORE
use Pod::Usage     qw[];
use Capture::Tiny  qw[];       # not in CORE
use Software::License;         # not in CORE
use Software::LicenseUtils;    # not in CORE
#
#
class App::mii v0.0.1 {
    method log ( $msg, @etc ) { say @etc ? sprintf $msg, @etc : $msg; }
    field $author;
    field $distribution;    # Required
    field $license;
    field $vcs;
    field $version;
    field $path;
    ADJUST {
        my $config = $self->slurp_config;
        $author       = $config->{author};
        $distribution = $config->{distribution};
        $license      = $config->{license};
        $vcs          = $config->{vcs};
        $version      = $config->{version};
        $path         = '.';
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
    };

    method dist() {
        my $eval = sprintf q[push @INC, './lib'; require %s; $%s::VERSION], $distribution, $distribution;
        $version = eval $eval;
        $path->child('META.json')->spew( JSON::Tiny::encode_json( $self->generate_meta ) );
        $vcs->add_file( $path->child('META.json') );
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

    method run( $cmd, @args ) {
        system $cmd, @args;
    }

    method usage( $msg, $sections //= () ) {
        Pod::Usage::pod2usage( -message => qq[$msg\n], -verbose => 99, -sections => $sections );
    }

    method generate_meta() {
        {
            # https://metacpan.org/pod/CPAN::Meta::Spec#REQUIRED-FIELDS
            abstract       => '',
            author         => $author,
            dynamic_config => 1,
            generated_by   => sprintf( 'App::mii %s', $App::mii::VERSION ),
            license        => [ map { $_->meta_name } @$license ],
            'meta-spec'    => { version => 2, url => 'https://metacpan.org/pod/CPAN::Meta::Spec' },
            name           => sub { join '-', split /::/, $distribution }
                ->(),
            release_status => 'stable',             # stable, testing, unstable
            version        => $version // v0.0.0,

            # https://metacpan.org/pod/CPAN::Meta::Spec#OPTIONAL-FIELDS
            description       => 'Not yet.',
            keywords          => [],
            no_index          => { file    => [], directory => [], package => [], namespace => [] },
            optional_features => { feature => { description => 'Not yet', prereqs => {} } },
            prereqs           => {
                runtime => {
                    requires   => { 'perl'         => '5.006', 'File::Spec' => '0.86', 'JSON' => '2.16' },
                    recommends => { 'JSON::XS'     => '2.26' },
                    suggests   => { 'Archive::Tar' => '0' },
                },
                build => { requires   => { 'Alien::SDL' => '1.00', } },
                test  => { recommends => { 'Test::Deep' => '0.10', } }
            },
            provides => {
                'Foo::Bar'       => { file => 'lib/Foo/Bar.pm', version => '0.27_02' },
                'Foo::Bar::Blah' => { file => 'lib/Foo/Bar/Blah.pm' },
                'Foo::Bar::Baz'  => { file => 'lib/Foo/Bar/Baz.pm', version => '0.3' },
            },
            resources => {
                homepage   => 'http://sourceforge.net/projects/module-build',
                license    => ['http://dev.perl.org/licenses/'],
                bugtracker => { web => 'http://rt.cpan.org/Public/Dist/Display.html?Name=CPAN-Meta', mailto => 'meta-bugs@example.com' },
                repository => { url => 'git://github.com/dagolden/cpan-meta.git', web => 'http://github.com/dagolden/cpan-meta', type => $vcs->name },
                x_twitter  => 'http://twitter.com/cpan_linked/'
            }
        };
    }

    method slurp_config() {
        my $dot_conf = Path::Tiny::path('.')->child('mii.conf');
        exit $self->log('mii.conf not found; to create a new project, try `mii help mint`') unless $dot_conf->is_file;
        JSON::Tiny::decode_json( $dot_conf->slurp() );
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
            $path->child( 'lib', @dir, $file . '.pm' )->spew(<<PM);
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
        $path->child( 't', '00_compile.t' )->spew(<<T);
use Test2::V0;
use lib './lib', '../lib';
use $distribution;
#
diag \$${distribution}::VERSION;
is ${distribution}::greet('World'), 'Hello, World', 'proper greeting';
#
done_testing;
T
        $path->child('LICENSE')->spew( join( '-' x 20 . "\n", map { $_->fulltext } @$license ) );
        $path->child('Changes')->spew( <<CHANGELOG );    # %v is non-standard and returns version number
# Changelog

All notable changes to this project will be documented in this file.

## [{{NEXT:%v}}] - {{NEXT:%Y-%m-%d}}

### Added

- This CHANGELOG file to hopefully serve as an evolving example of a
  standardized open source project CHANGELOG.
- See https://keepachangelog.com/en/1.1.0/

CHANGELOG

        # TODO: cpanfile
        $path->child('cpanfile')->spew(<<'CPAN');
requires perl => v5.38.0;

on configure =>{};
on build=>{};
on test => {
    requires 'Test2::V0';
};
on configure=>{};
on runtime=>{};
CPAN
        $path->child('Build.PL')->spew(<<BUILD_PL);
#!perl
use lib '.';
use builder::mbt;
builder::mbt::Build_PL();
BUILD_PL
        $path->child( 'builder', 'mbt.pm' )->touchpath->spew( <<'BUILDER' );    # TODO: builder/$dist.pm        if requested
package builder::mbt v0.0.1 {    # inspired by Module::Build::Tiny 0.047
    use strict;
    use warnings;
    use v5.26;
    $ENV{PERL_JSON_BACKEND} = 'JSON::PP';
    use CPAN::Meta;
    use ExtUtils::Config 0.003;
    use ExtUtils::Helpers 0.020 qw/make_executable split_like_shell detildefy/;
    use ExtUtils::Install qw/pm_to_blib install/;
    use ExtUtils::InstallPaths 0.002;
    use File::Find            ();
    use File::Spec::Functions qw/catfile catdir rel2abs abs2rel splitdir curdir/;
    use Getopt::Long 2.36     qw/GetOptionsFromArray/;
    use JSON::Tiny            qw[];                                                 # Not in CORE
    use Path::Tiny            qw[];                                                 # Not in CORE

    sub get_meta {
        state $metafile //= Path::Tiny::path('META.json');
        exit say "No META information provided\n" unless $metafile->is_file;
        return CPAN::Meta->load_file( $metafile->realpath );
    }

    sub find {
        my ( $pattern, $dir ) = @_;
        my @ret;
        File::Find::find( sub { push @ret, $File::Find::name if /$pattern/ && -f }, $dir ) if -d $dir;
        return @ret;
    }

    sub contains_pod {
        my ($file) = @_;
        return unless -T $file;
        return Path::Tiny::path($file)->slurp =~ /^\=(?:head|pod|item)/m;
    }
    my %actions;
    %actions = (
        build => sub {
            my %opt = @_;
            for my $pl_file ( find( qr/\.PL$/, 'lib' ) ) {
                ( my $pm = $pl_file ) =~ s/\.PL$//;
                system $^X, $pl_file, $pm and die "$pl_file returned $?\n";
            }
            my %modules = map { $_ => catfile( 'blib', $_ ) } find( qr/\.pm$/,  'lib' );
            my %docs    = map { $_ => catfile( 'blib', $_ ) } find( qr/\.pod$/, 'lib' );
            my %scripts = map { $_ => catfile( 'blib', $_ ) } find( qr/(?:)/,   'script' );
            my %sdocs   = map { $_ => delete $scripts{$_} } grep {/.pod$/} keys %scripts;
            my %dist_shared
                = map { $_ => catfile( qw/blib lib auto share dist/, $opt{meta}->name, abs2rel( $_, 'share' ) ) } find( qr/(?:)/, 'share' );
            my %module_shared
                = map { $_ => catfile( qw/blib lib auto share module/, abs2rel( $_, 'module-share' ) ) } find( qr/(?:)/, 'module-share' );
            pm_to_blib( { %modules, %docs, %scripts, %dist_shared, %module_shared }, path('.')->child(qw[blib lib auto]) );
            make_executable($_) for values %scripts;
            path('.')->child(qw[blib arch])->mkdir( { verbose => $opt{verbose} } );
            return 0;
        },
        test => sub {
            my %opt = @_;
            $actions{build}->(%opt) if not -d 'blib';
            require TAP::Harness::Env;
            my %test_args = (
                ( verbosity => $opt{verbose} ) x !!exists $opt{verbose},
                ( jobs  => $opt{jobs} ) x !!exists $opt{jobs},
                ( color => 1 ) x !!-t STDOUT,
                lib => [ map { rel2abs( catdir( qw/blib/, $_ ) ) } qw/arch lib/ ],
            );
            my $tester = TAP::Harness::Env->create( \%test_args );
            return $tester->runtests( sort +find( qr/\.t$/, 't' ) )->has_errors;
        },
        install => sub {
            my %opt = @_;
            $actions{build}->(%opt) if not -d 'blib';
            install( $opt{install_paths}->install_map, @opt{qw/verbose dry_run uninst/} );
            return 0;
        },
        clean => sub {
            my %opt = @_;
            path($_)->remove_tree( { verbose => $opt{verbose} } ) for qw[blib temp Build _build_params MYMETA.yml MYMETA.json];
            return 0;
        },
    );

    sub Build {
        my $action = @ARGV && $ARGV[0] =~ /\A\w+\z/ ? shift @ARGV : 'build';
        $actions{$action} // exit say "No such action: $action";
        my $build_params = Path::Tiny::path('_build_params');
        my ( $env, $bargv ) = $build_params->is_file ? @{ JSON::Tiny::decode_json( $build_params->slurp ) } : ();
        my %opt;
        GetOptionsFromArray( $_, \%opt,
            qw/install_base=s install_path=s% installdirs=s destdir=s prefix=s config=s% uninst:1 verbose:1 dry_run:1 pureperl-only:1 create_packlist=i jobs=i/
        ) for grep {defined} $env, $bargv, \@ARGV;
        $_ = detildefy($_) for grep {defined} @opt{qw/install_base destdir prefix/}, values %{ $opt{install_path} };
        @opt{ 'config', 'meta' } = ( ExtUtils::Config->new( $opt{config} ), get_meta() );
        exit $actions{$action}->( %opt, install_paths => ExtUtils::InstallPaths->new( %opt, dist_name => $opt{meta}->name ) );
    }

    sub Build_PL {
        my $meta = get_meta();
        printf "Creating new 'Build' script for '%s' version '%s'\n", $meta->name, $meta->version;
        Path::Tiny::path('Build')->spew("#!$^X\nuse Module::Build::Tiny;\nBuild();\n");
        make_executable('Build');
        my @env = defined $ENV{PERL_MB_OPT} ? split_like_shell( $ENV{PERL_MB_OPT} ) : ();
        Path::Tiny::path('_build_params')->spew( JSON::Tiny::encode_json( [ \@env, \@ARGV ] ) );
        $meta->save('MYMETA.json');
    }
}
1;
BUILDER

        # TODO: .github/workflow/*      in ::Git
        # TODO: .github/FUNDING.yaml    in ::Git
        # Finally...
        $path->child('mii.conf')->spew( JSON::Tiny::encode_json( $self->config() ) );
        $self->log( 'New project minted in %s', $path->realpath );
        my $cwd = Path::Tiny::path('.')->realpath;
        chdir $path->realpath->stringify;
        $self->log( $vcs->init() );
        $self->log( $vcs->add_file('.') );
        chdir $cwd;
    }
}

class App::mii::Mint::Subclass : isa(App::mii::Mint::Base) { }

class App::mii::VCS::Base {
    method whoami()         { () }
    method init()           {...}
    method add_file($path)  {...}
    method gather_files()   {...}
    method diff_file($path) {...}
    method diff_repo()      {...}
    method commit($message) {...}
    method tag($name)       {...}
    method push             {...}
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

    method init () {
        my $msg = Capture::Tiny::capture_stdout { system qw[git init] };
        chomp $msg;
        $msg;
    }

    method add_file($path) {
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
1;

=encoding utf-8

=head1 NAME

App::mii - Internals for mii

=head1 SYNOPSIS

    $ mii help

=head1 DESCRIPTION

App::mii is just for me.

If I forget how to use mii, I could install it and run C<mii help> or I could check the POD at the end of F<script/mii.pl>

=head1 LICENSE

Copyright (C) Sanko Robinson.

This library is free software; you can redistribute it and/or modify it under the terms found in the
Artistic License 2. Other copyrights, terms, and conditions may apply to data transmitted through
this module.

=head1 AUTHOR

Sanko Robinson E<lt>sanko@cpan.orgE<gt>

=begin stopwords

mii

=end stopwords

=cut
