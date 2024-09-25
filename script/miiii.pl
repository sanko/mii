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
    method log ( $msg, @etc ) { say @etc ? sprintf $msg, @etc : $msg; }
    use JSON::PP   qw[decode_json];    # not in CORE
    use Path::Tiny qw[];               # not in CORE
    use version    qw[];
    #
    field $path : param : reader //= '.';
    #
    field $config : reader;
    field $meta;
    #
    method abstract( $v //= () ) { $config->{abstract} = $v if defined $v; $config->{abstract}; }
    method version( $v //= () )  { $config->{version} = $v if defined $v; version::parse( 'version', $config->{version} ); }
    method name ()               { $config->{name} }
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
    ADJUST {
        $path   = Path::Tiny::path($path) unless builtin::blessed $path;
        $config = decode_json $path->child('META.json')->slurp_raw;
    }

    # init
    method init($package) {
        $path->child($_)->touchpath for qw[t lib script];
    }

    # Pull list of files from git
    method gather_files() {
        my $msg = Capture::Tiny::capture_stdout { system qw[git ls-files] };
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

    method write_cpanmeta() {
        my $cpanfile = Module::CPANfile->load;
        $cpanfile->merge_meta( $path->child('META.json'), '2.0' );
        use Data::Dump;
        ddx $cpanfile;
        warn $cpanfile->to_string(1);
        $cpanfile->save('cpanfile');
    }

    method make_dist(%args) {

        # %args might contain version, etc.
    }
    method make_test( $verbose //= 0 ) { }
};
#
use Data::Dump;
my $mii = App::mii->new();
ddx $mii->gather_files;

#~ ddx $mii->generate_meta;
$mii->write_meta;
