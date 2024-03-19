# mii new Module::Name
# mii help [command]
# mii test
# mii dist
# mii install
# mii release
#
use v5.38;
use Pod::Usage;
use Getopt::Long;
use lib '../lib';
use App::mii;

#~ @ARGV = qw[nefdsaw --license perl_5];
#~ @ARGV = qw[new Acme::Anvil];
pod2usage( -verbose => 99, -sections => [qw[NAME SYNOPSIS Commands/Commands]], -exitval => 0 ) unless @ARGV;
my %commands = (
    new => sub ( $package //= (), @args ) {
        $package // App::mii->new->usage( 'mii: Minting a new distribution requires a package name.', 'Commands/new' );
        Getopt::Long::GetOptionsFromArray(
            \@args,
            'author=s'  => \my $author,
            'license=s' => \my $license,
            verbose     => \my $verbose    # flag
        );
        my $minter = App::mii::Mint::Base->new( distribution => $package, author => $author, license => $license, path => '.' );

        #~ say 'TODO';
        #~ warn ref $minter;
        #~ say $minter->license->fulltext;
        $minter->spew_config;
        exit 0;
    },
    help => sub( $subcommand //= () ) {
        pod2usage( -verbose => 99, -sections => [ qw[SYNOPSIS], 'Commands/' . ( $subcommand // 'Commands' ) ], -exitval => 0 );
    },
    test    => sub { },
    dist    => sub { },
    install => sub { },
    release => sub { },
    version => sub { say 'mii: ' . $App::mii::VERSION . ' - https://github.com/sanko/mii' }
);
my $command = shift @ARGV;
#
exit !$commands{$command}->(@ARGV) if defined $commands{$command};
exit say "Unknown command: $command";

=pod

=head1 NAME

mii - Just a little test

=head1 SYNOPSIS

mii [command] [options]

=head1 Commands

    mii [command] [optons]

=head2 Commands

    new Module::Name [options]  mint a new distribution
    help [command]              brief help message
    version                     display version information

For more on each command, try 'mii help new' or 'mii help help'

=head2 new

Mint a new distribution.

Examples:

    mii new Acme::Anvil --vcs=git --license=artistic_2

=head3 Options

    --vcs           your version control system of choice (default is git)
    --license       your software license of choice (default is artistic_2)
    --builder       your build system of choice

=head2 help

Print a brief help message and exits.

To get help with a specific command, try 'mii help new'

=head2 version

Prints version information and exits.

=head1 DESCRIPTION

B<This program> will read the given input file(s) and do something useful with the contents thereof.

=cut
