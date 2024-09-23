use v5.40;
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
use App::mii::Markdown;
use App::mii::Templates;
#
class App::mii v0.0.1 {
    method log ( $msg, @etc ) { say @etc ? sprintf $msg, @etc : $msg; }
    field $author : param : reader //= ();
    field $distribution : param : reader;    # Required
    field $license : param : reader //= 'artistic_2';
    field $vcs : reader = 'git';
    field $version : param : reader;
    field $path : param : reader //= Path::Tiny::path('.')->realpath;
    field $config : param : reader;
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
                git => 'App::mii::VCS::Git',

                #~ hg     => 'App::mii::VCS::Mercurial',
                #~ brz    => 'App::mii::VCS::Breezy',
                #~ fossil => 'App::mii::VCS::Fossil',
                #~ svn    => 'App::mii::VCS::Subversion'
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
        eval system 'tidyall -a';
        system $^X, $path->child('Build.PL')->stringify;
        system $^X, $path->child('Build')->stringify;

        #~ TODO: update version number in Changelog, run Build.PL, etc.
        eval 'use Test::Spellunker; 1' && Test::Spellunker::all_pod_files_spelling_ok();

        # TODO: Also spell check changelog
        system $^X, $path->child('Build')->stringify, 'test';
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
            require Archive::Tar;
            my $arch = Archive::Tar->new;
            $arch->add_files( grep { !/mii\.conf/ } $self->gather_files );
            $_->mode( $_->mode & ~022 ) for $arch->get_files;
            my $dist = sprintf '%s::%s.tar.gz', $distribution, $version;
            $dist =~ s[::][-]g;
            $dist = Path::Tiny::path($dist)->canonpath;
            $arch->write( $dist, &Archive::Tar::COMPRESS_GZIP() );
            return -s $dist;
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
            $path->child( 'lib', @dir, $file . '.pm' )
                ->spew_utf8( App::mii::Templates::lib_blah_pm( $distribution, $version, $author, $license_blurb ) );
        }
        $path->child($_)->mkdir for qw[builder eg t];
        $path->child( 't', '00_compile.t' )->spew_utf8( App::mii::Templates::t_00_comple_t($distribution) );
        $path->child('LICENSE')->spew_utf8( join( '-' x 20 . "\n", map { $_->fulltext } @$license ) );
        $path->child('Changes.md')->spew_utf8( App::mii::Templates::changes_md() );
        $path->child('cpanfile')->spew_utf8( App::mii::Templates::cpanfile() );
        $path->child('Build.PL')->spew_utf8( App::mii::Templates::build_pl() );
        $path->child( 'builder', 'mbt.pm' )->touchpath->spew_utf8( App::mii::Templates::builder_pm() );

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
1;
