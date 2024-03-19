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
    method log ($msg) { say $msg; }

    method usage( $msg, $sections //= () ) {
        Pod::Usage::pod2usage( -message => qq[$msg\n], -verbose => 99, -sections => $sections );
    }
};

class App::mii::Mint::Base {
    field $author : param //= ();    # We'll ask VSC as a last resort
    field $distribution : param;     # Required
    field $license : param //= 'artistic_2';
    field $vcs : param     //= 'git';
    field $path : param    //= '.';
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
        $author //= $vcs->whoami;
        $author // exit $self->log(q[Unable to guess author's name. Help me out and use --author]);
        if ( !builtin::blessed $license ) {
            my ($pkg) = Software::LicenseUtils->guess_license_from_meta_key($license);
            exit $self->log(qq[Software::License has no knowledge of "$license"]) unless $pkg;
            $license = $pkg->new( { holder => $author, Program => $distribution } );
        }
        if ( !builtin::blessed $path ) {
            $path = Path::Tiny::path($path);
        }
    }
    method license() {$license}
    method vcs()     {$vcs}

    method spew_config() {
        $path->child('mii.conf')->spew( JSON::Tiny::encode_json( $self->config() ) );
    }

    method config() {
        +{ author => $author, distribution => $distribution, license => $license->meta_name, vcs => $vcs->name };
    }
}

class App::mii::Mint::Subclass : isa(App::mii::Mint::Base) { }

class App::mii::VCS::Base {
    method whoami()         { () }
    method add_file($path)  {...}
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
__END__

=encoding utf-8

=head1 NAME

App::mii - Internals for mii

=head1 SYNOPSIS

    use App::mii;

=head1 DESCRIPTION

App::mii is just for me.

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

