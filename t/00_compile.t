use v5.38;
use Test2::V0;
use Capture::Tiny qw[capture];
use Path::Tiny    qw[path tempdir];
use lib '../lib';
use App::mii;
diag 'App::mii ' . $App::mii::VERSION;
my ($mii_pl) = map { $_->realpath } grep { $_->exists } map { path(qq[$_/script/mii.pl]); } '.', '..';
#
my $cwd = path('.')->realpath;
subtest live => sub {
    $mii_pl // skip_all 'failed to locate mii.pl';
    diag qq[found mii.pl at $mii_pl];
    subtest '$ mii' => sub {
        my ( $stdout, $stderr, $exit ) = capture { system( $^X, $mii_pl ) };
        is $exit, 0, 'exit ok';
        like $stdout, qr[Usage], 'usage';
    };
    subtest '$ mii help' => sub {
        my ( $stdout, $stderr, $exit ) = capture { system( $^X, $mii_pl, 'help' ) };
        is $exit, 0, 'exit ok';
        like $stdout, qr[Usage], 'usage';
    };
    subtest '$ mii new' => sub {
        my ( $stdout, $stderr, $exit ) = capture { system( $^X, $mii_pl, 'new' ) };
        isnt $exit, 0, 'exit error';
        like $stdout, qr[requires a package], 'missing package name';
    };
    subtest '$ mii new Acme::Anvil --author=John Smith' => sub {
        my ( $stdout, $stderr, $exit, $outdir ) = run_mii( qw[new Acme::Anvil], '--author=John Smith' );
        is $exit, 0, 'exit ok';
        diag $stdout;
        diag $stderr;
        $outdir->visit( sub { diag $_->realpath }, { recurse => 1 } );
        diag $outdir->child('mii.conf')->slurp;

        #~ like $stdout, qr[requires a package], 'missing package name';
    };
    subtest '$ mii new Acme::Anvil --license=perl_5' => sub {
        my ( $stdout, $stderr, $exit, $outdir ) = run_mii( qw[new Acme::Anvil --license=perl_5], '--author=John Smith' );
        is $exit, 0, 'exit ok';
        diag $stdout;
        diag $stderr;
        $outdir->visit( sub { diag $_->realpath }, { recurse => 1 } );

        #~ like $stdout, qr[requires a package], 'missing package name';
    };
};

sub run_mii (@args) {
    my $temp = tempdir();
    diag qq[working in $temp];
    chdir $temp->canonpath;
    my ( $stdout, $stderr, $errno ) = capture {
        system( $^X, '-I' . $cwd->child('../lib')->canonpath, $mii_pl, @args )
    };
    chdir $cwd->canonpath;
    ( $stdout, $stderr, $errno, $temp );
}
done_testing;
