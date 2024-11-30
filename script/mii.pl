#!perl
# mii mint Module::Name
# mii help [command]
# mii test
# mii dist
# mii disttest
# mii release
#
use v5.38;
use Pod::Usage;
use lib '../lib';
use App::mii;

#~ @ARGV = qw[mint Acme::Anvil --license artistic_2];
#~ @ARGV = qw[mint Acme::Anvil];
#~ @ARGV = qw[mint];
#~ @ARGV = qw[dist];
pod2usage( -verbose => 99, -sections => [qw[NAME SYNOPSIS Commands/Commands]], -exitval => 0 ) unless @ARGV;
my ( %args, @args );
for my $arg (@ARGV) {
    if ( $arg =~ /^-/ ) {
        if ( $arg =~ /-+([^=]+)(?:=(.+))?/ ) {
            $args{$1} = $2 ? $2 : 1;
        }
    }
    else {
        push @args, $arg;
    }
}
my %commands = (
    mint => sub ( $package //= (), @args ) {
        my $mii = App::mii->new();
        $package //= $mii->prompt('Minting new dist. Package name');
        $package
            // pod2usage( -message => 'mii: Minting a new distribution requires a package name', -verbose => 99, -sections => ['Commands/mint'] );
        $mii->name($package);

        #~ $mii->license(@license?@license: ['artistic_2']);
        #~ $mii->author($author);
        #~ die $version;
        $mii->init( $package, v1.0.0 );

        #~ $mii->author([$author});
        die 'I should be generating a META.json here';

        #~ App::mii::Mint::Base->new( distribution => $package, author => $author, vcs => $vcs, license => \@license )->mint;
    },
    help => sub( $subcommand //= () ) {
        pod2usage( -verbose => 99, -sections => [ qw[SYNOPSIS], 'Commands/' . ( $subcommand // 'Commands' ) ], -exitval => 0 );
    },
    test     => sub { App::mii->new()->step_test(@_) },
    tidy     => sub {...},                                                                      # Run tidyall -a
    dist     => sub { App::mii->new()->dist(@_); },
    disttest => sub { App::mii->new()->disttest(@_); },
    release  => sub { App::mii->new()->release(@_); },
    version  => sub { say 'mii: ' . $App::mii::VERSION . ' - https://github.com/sanko/mii' },

    # testing commands
    list => sub {
        say $_ for App::mii->new()->gather_files();
    }
);
my $command = shift @args;
#
exit !$commands{$command}->(%args) if defined $commands{$command};
exit say "Unknown command: $command";

=pod

=head1 NAME

mii - Just a little test

=head1 SYNOPSIS

mii [command] [options]

=head1 Commands

    mii [command] [optons]

=head2 Commands

    mint Module::Name [options]     mint a new distribution
    help [command]                  brief help message
    version                         display version information
    dist                            build a dist
    disttest                         build a dist and test it with cpanminus
    release                         build a dist and (maybe) upload it to PAUSE

For more on each command, try 'mii help mint' or 'mii help help'

=head2 mint

Mint a new distribution.

Examples:

    mii mint Acme::Anvil --license=artistic_2

=head3 Options

    --author        your name and email address
    --license       your software license(s) of choice (default is artistic_2)

=head2 help

Print a brief help message and exits.

To get help with a specific command, try 'mii help mint'

=head2 version

Prints version information and exits.

=head2 dist

Build a dist. Most metadata (not including the changelog) is updated.

=head3 Options

    --verbose     be noisy

=head2 disttest

Build a dist and test it with cpanminus. Most metadata (not including the changelog) is updated.

=head3 Options

    --verbose     be noisy

=head2 release

Build a dist and upload it to PAUSE. All metadata (including the changelog) is updated before release.

=head3 Options

    --verbose     be noisy
    --pause       upload to PAUSE without prompting us
    --tag         tag the release in git without prompting us

=head1 DESCRIPTION

B<This program> will read the given input file(s) and do something useful with the contents thereof.

=for stopwords mii

=cut
