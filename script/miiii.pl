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
    use CPAN::Meta qw[];
    #
    field $path : param : reader //= '.';

    #~ field $package : param //= ();
    #
    field $config : reader;
    field $meta;
    #
    method abstract( $v //= () )    { $config->{abstract} = $v if defined $v; $config->{abstract}; }
    method description( $v //= () ) { $config->{description} = $v if defined $v; $config->{description} }
    method version( $v //= () )     { $config->{version} = $v if defined $v; version::parse( 'version', $config->{version} ); }
    method name ( $v //= () )       { $config->{name} = $v =~ s[::][-]gr if defined $v; $config->{name} }
    method distribution ()          { $config->{name} =~ s[-][::]gr }
    method author ()                { $config->{author} //= $self->whoami }

    method license () {
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
        $path = $path->child( $self->name ) if defined $self->name;
        if ( $meta->exists ) {
            $config = CPAN::Meta->load_file($meta);

            #~ $config = decode_json $meta->slurp_utf8;
        }

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
        map { Path::Tiny::path($_)->canonpath } split /\R+/, $msg;
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
                    perl                     => 'v5.40.0'
                }
            }
        );
        for my $href ( Module::CPANfile->load->prereq_specs, $config->{prereqs} ) {
            for my ( $stage, $mods )(%$href) {
                for my ( $mod, $version )(%$mods) {
                    $prereqs{$stage}{$mod} //= $version;
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

    method spew_meta () {    # I could use CPAN::Meta but...
        state $json //= JSON::PP->new->utf8->pretty->indent->core_bools->canonical->allow_nonref;
        $path->child('META.json')->spew_utf8( $json->encode( $self->generate_meta ) ) && $self->log( 'Wrote META.json in %s', $path->absolute );
    }

    method spew_cpanfile() {
        my $cpanfile = Module::CPANfile->from_prereqs( $self->generate_meta->{prereqs} );
        $cpanfile->save( $path->child('cpanfile') );
    }

    method spew_license() {
        $path->child('LICENSE')->spew_utf8( join( '-' x 20 . "\n", map { $_->fulltext } $self->license ) );
    }

    method spew_builder() {
        my $dist = $self->distribution;
        $path->child('Build.PL')->spew_utf8( <<END );
use v5.40;
use lib 'builder';
use ${dist}::Builder;
${dist}::Builder->new->Build_PL();
END

        #~ $self->package2path( $self->distribution, 'builder' )->spew_utf8( sprintf         <<'', $self->distribution, $self->distribution );
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
        $file->spew_utf8( <<END) }
package $package $version {
    ;
};
1;
__END__
=encoding utf-8

=head1 NAME

$package - $abstract

=head1 SYNOPSIS

    use $package;
    ...;

=head1 DESCRIPTION

$description

=head1 See Also

TODO

=head1 LICENSE

$license

See the F<LICENSE> file for full text.

=head1 AUTHOR

$author

=begin stopwords


=end stopwords

=cut
END

    method dist(%args) {

        #~ eval system 'tidyall -a';
        #~ system $^X, $path->child('Build.PL')->stringify;
        #~ system $^X, $path->child('Build')->stringify;
        #~ TODO: update version number in Changelog, run Build.PL, etc.
        #~ eval 'use Test::Spellunker; 1' && Test::Spellunker::all_pod_files_spelling_ok();
        # TODO: Also spell check changelog
        #~ system $^X, $path->child('Build')->stringify, 'test';
        #~ $path->child('META.json')->spew_utf8( $json->utf8->pretty(1)->allow_blessed(1)->canonical->encode( $self->generate_meta() ) );
        #~ $vcs->add_file( $path->child('META.json') );
        {
            ;

            #~ my @dir        = split /::/, $distribution;
            #~ my $file       = pop @dir;
            #~ my $readme_src = $path->child( $config->{readme_from} // ( 'lib', @dir, $file . '.pod' ) );
            #~ my $readme_src = $path->child( 'lib', split('::', $self->distribution) . '.pm' ) unless $readme_src->exists;
            #~ $path->child('README.md')->spew_utf8( App::mii::Markdown->new->parse_from_file( $readme_src->canonpath )->as_markdown )
            #~ if $readme_src->exists;
        }
        {
            require Archive::Tar;
            require List::Util;
            my $arch = Archive::Tar->new;
            $arch->add_files(
                grep {
                    my $re = $_;
                    not List::Util::any { $_ =~ /$re/ } @{ $config->{'x_ignore'} }
                } $self->gather_files
            );
            $_->mode( $_->mode & ~022 ) for $arch->get_files;
            my $dist = Path::Tiny::path( $self->name . '-' . $self->version . '.tar.gz' )->canonpath;
            $arch->write( $dist, &Archive::Tar::COMPRESS_GZIP() );
            return -s $dist;
        }
    }

    method test( $verbose //= 0 ) {
        $self->build unless -d 'blib';
        $self->run( $^X, 'Build', 'test' );
    }

    method release( $upload //= 1 ) {
    }

    method init( $pkg //= $self->prompt('Package name'), $ver //= v1.0.0 ) {
        $self->name($pkg);
        $self->version($ver);
        $path = $path->child( $self->name );
        $config->{license} //= ['artistic_2'];
        {
            $path->child($_)->mkdir for qw[t lib script eg share];
            $self->spew_package( $self->distribution );
            $self->spew_meta;
            $self->spew_cpanfile;
            $self->spew_license;
            $self->spew_builder;

            # TODO: .tidyallrc
            #
            $self->package2path( $self->distribution );    #->touch;
        }

        # TODO: create t/000_compile.t
        $self->git( 'init', $path );
        $_->touchpath for map { $path->child($_) } qw[t lib script eg share];
        $self->git( 'add', '.' );
    }

    method run( $exe, @args ) {
        $self->log( join ' ', '$', $exe, @args );
        my ( $stdout, $stderr, $exit ) = Capture::Tiny::capture { system $exe, @args; };
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
        my ( $stdout, $stderr, $exit ) = $self->git( 'log', '--format="%aN <%aE>"' );
        !$exit or return ();
        my %uniq;
        my @authors = map {m[^.+ <(.+?)>$]} @{ $self->author };
        for my $pal ( split /\n/, $stdout ) {
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
use Data::Dump;
$|++;
my $command = @ARGV ? shift @ARGV : 'dist';
my $mii     = App::mii->new(

    #~ package => 'Net::BitTorrent'
    #~ path => 'Acme-Mii/'
);
my $method = $mii->can($command);
$method // exit !say 'Cannot run command: ' . $command;
$method->( $mii, @ARGV );
