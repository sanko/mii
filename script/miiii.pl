#!perl
# This is mii2
use v5.40;
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
use App::mii::Templates;
#
class App::mii v1.0.0 {
    use JSON::PP qw[decode_json];    # not in CORE
    use Path::Tiny qw[];             # not in CORE
    use version    qw[];
    #
    field $path : param : reader //= '.';
    field $package : param //= ();
    #
    field $config : reader;
    field $meta;
    #
    method abstract( $v //= () ) { $config->{abstract} = $v if defined $v; $config->{abstract}; }
    method version( $v //= () )  { $config->{version} = $v if defined $v; version::parse( 'version', $config->{version} ); }
    method name ( $v //= () )    { $config->{name} = $v =~ s[::][-]gr if defined $v; $config->{name} }
    method package ()            { $config->{name} =~ s[-][::]gr }
    method author ()             { $config->{author} }

    method license () {
        map {
            my ($pkg) = Software::LicenseUtils->guess_license_from_meta_key($_);
            exit $self->log( qq[Software::License has no knowledge of "%s"], $_ ) unless $pkg;
            $pkg
        } @{ $config->{license} };
    }
    #
    method log ( $msg, @etc ) { say @etc ? sprintf $msg, @etc : $msg; }

    method package2path($package) {
        $path->child('lib')->child( ( $package =~ s[::][/]gr ) . '.pm' );
    }
    #
    ADJUST {
        $path = Path::Tiny::path($path)->absolute unless builtin::blessed $path;
        my $meta = $path->child('META.json');
        warn;
        if ( $meta->exists ) {
            $config = decode_json $meta->slurp_utf8;
            warn;
        }
        elsif ( defined $package ) {
            $self->name($package);
            warn;
        }
        else {
            die '...what are we doing? I need a package name or something.';
        }
        warn;
    }

    # Pull list of files from git
    method gather_files() {
        my ($msg) = $self->git('ls-files');
        warn $msg;
        map { Path::Tiny::path($_)->canonpath } split /\R+/, $msg;
    }

    method generate_meta() {
        my $stable = !$self->version->is_alpha;
        exit $self->log( 'No modules found in ' . $path->child('lib') ) unless $path->child('lib')->children;
        my $provides = $stable ? Module::Metadata->provides( dir => $path->child('lib')->canonpath, version => 2 ) : {};
        $_->{file} =~ s[\\+][/]g for values %$provides;
        +{
            # Retain clutter
            ( map { $_ => $config->{$_} } grep {/^x_/} keys %$config ),

            # https://metacpan.org/pod/CPAN::Meta::Spec#REQUIRED-FIELDS
            abstract       => $self->abstract,
            author         => $self->author,
            dynamic_config => 1,                                                                      # lies
            generated_by   => sprintf( 'App::mii %s', $App::mii::VERSION ),
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
            prereqs => $config->{prereqs} // do { Module::CPANfile->load->prereq_specs }
                // {},
            provides  => $provides,                                                                   # blank unless stable
            resources => { ( defined $config->{resources} ? %{ $config->{resources} } : () ), license => [ map { $_->url } $self->license ] },
        };
    }

    method write_meta () {
        state $json //= JSON::PP->new->utf8->pretty->indent->core_bools->canonical->allow_nonref;
        $path->child('META.json')->spew_utf8( $json->encode( $self->generate_meta ) );
    }

    method write_cpanfile() {
        my $cpanfile = Module::CPANfile->from_prereqs( $self->generate_meta->{prereqs} );
        $cpanfile->save( $path->child('cpanfile') );
    }

    method write_pm( $package, $version //= $self->version ) {
        my $file = $self->package2path($package);
        return if $file->exists;
        $file->touchpath;
        $file->spew_utf8( sprintf <<'END', $package, $version ) }
package %s %s { ; }; 1;
__END__
END

    method dist(%args) {

        # %args might contain version, etc.
    }
    method test( $verbose //= 0 ) { }

    method release( $upload //= 1 ) {
    }

    method init() {
                warn;

        {
            $path->child($_)->mkdir for qw[t lib script eg share];
        warn;

            # TODO: Create lib/.../....pm
            $self->write_pm( $self->package );
                    warn;

            $self->write_meta;
                    warn;

            $self->write_cpanfile;
        warn;

            # TODO: .tidyallrc
            #
                    warn;

            warn $self->package2path( $self->package );    #->touch;
        }
        warn;

        # TODO: create t/000_compile.t
        $self->git( 'init', $path );
                warn;

        $self->git( 'add',  $_ ) for qw[cpanfile META.json];
                warn;

        for my $dir ( map { $path->child($_) } qw[t lib script eg share] ) {
                    warn;

            $dir->touchpath;
                    warn;

            $self->git( 'add', $dir );
                    warn;

        }
                warn;

    }

    method git(@args) {
warn;
        #~ warn join ' ', '>> git', @args;
        my ( $stdout, $stderr, $exit ) = Capture::Tiny::capture {
            system 'git', @args;
        };

        #~ use Data::Dump;
        #~ ddx [ $stdout, $stderr, $exit ];
        #~ $stdout;
    }

        method whoami() {
        my $me = Capture::Tiny::capture_stdout { system qw[git config user.name] };
        my $at = Capture::Tiny::capture_stdout { system qw[git config user.email] };
        $me // return ();
        chomp $me;
        chomp $at if $at;
        $me . ( $at ? qq[ <$at>] : '' );
    }
};
#
use Data::Dump;
$|++;

#~ chdir
my $mii = App::mii->new(
    package => 'Net::BitTorrent',

    #~ path => 'Acme-Mii/'
);
warn;
$mii->init();
warn;

#~ warn $mii->package2path('Acme::Mii');
#~ ddx $mii->gather_files;
#~ ddx $mii->generate_meta;
ddx $mii->gather_files;
warn;
