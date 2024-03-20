use v5.38;
use feature 'class';
no warnings 'experimental::class', 'experimental::builtin';
use Carp           qw[];
use Template::Tiny qw[];       # not in CORE
use JSON::Tiny     qw[];       # not in CORE
use Path::Tiny     qw[];       # not in CORE
use Pod::Usage     qw[];
use Capture::Tiny  qw[];       # not in CORE
use Software::License;         # not in CORE
use Software::LicenseUtils;    # not in CORE
#
class App::mii v0.0.1 {
    method log ( $msg, @etc ) { say @etc ? sprintf $msg, @etc : $msg; }
    field $author;
    field $distribution;       # Required
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
        if ( !builtin::blessed $license ) {
            my ($pkg) = Software::LicenseUtils->guess_license_from_meta_key($license);
            exit $self->log(qq[Software::License has no knowledge of "$license"]) unless $pkg;
            $license = $pkg->new( { holder => $author, Program => $distribution } );
        }
        if ( !builtin::blessed $path ) {
            $path = Path::Tiny::path($path)->realpath;
        }

        # TODO: move to ::Dist
        $self->generate_meta;
    };

    method usage( $msg, $sections //= () ) {
        Pod::Usage::pod2usage( -message => qq[$msg\n], -verbose => 99, -sections => $sections );
    }

    method generate_meta() {
        my $meta = {

            # https://metacpan.org/pod/CPAN::Meta::Spec#REQUIRED-FIELDS
            abstract       => '',
            author         => $author,
            dynamic_config => 1,
            generated_by   => sprintf( 'App::mii %s', $App::mii::VERSION ),
            license        => [ map { $_->meta_name } @$license ],
        };
        #~ use Data::Dump;
        #~ ddx $meta;
    }

    method slurp_config() {
        my $dot_conf = Path::Tiny::path('.')->child('mii.conf');
        exit $self->log('mii.conf not found; to create a new project, try `mii help mint`') unless $dot_conf->is_file;
        JSON::Tiny::decode_json( $dot_conf->slurp() );
    }
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

    method hit_it() {
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
        $path->child('eg')->mkdir;
        $path->child('t')->mkdir;
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
        # TODO: Build.PL
        # TODO: builder/$dist.pm        if requested
        # TODO: .github/workflow/*      in ::Git
        # TODO: .github/FUNDING.yaml    in ::Git
        # TODO: META.json               in ::Dist?
        # Finally...
        $path->child('mii.conf')->spew( JSON::Tiny::encode_json( $self->config() ) );
        $self->log( 'New project minted in %s', $path->realpath );
        my $cwd = Path::Tiny::path('.')->realpath;
        chdir $path->realpath->stringify;
        $self->log( $vcs->init() );
        $self->log( $vcs->add_file('.') );
        chdir $cwd;
        0;
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
