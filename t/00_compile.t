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
    subtest '$ mii mint' => sub {
        my ( $stdout, $stderr, $exit ) = capture { system( $^X, $mii_pl, 'mint' ) };
        isnt $exit, 0, 'exit error';
        like $stdout, qr[requires a package], 'missing package name';
    };
    subtest '$ mii mint Acme::Anvil --author=John Smith' => sub {
        my $outdir = tempdir();
        my ( $stdout, $stderr, $exit ) = run_mii( $outdir, qw[mint Acme::Anvil], '--author=John Smith' );
        is $exit, 0, 'exit ok';
        diag $stdout;
        diag $stderr;
        $outdir->visit( sub { diag $_->realpath }, { recurse => 1 } );
        diag $outdir->child( 'Acme-Anvil', 'mii.conf' )->slurp;
        like $outdir->child( 'Acme-Anvil', 'LICENSE' )->slurp, qr[The Artistic License 2.0], 'default license file';

        #~ like $stdout, qr[requires a package], 'missing package name';
    };
    subtest '$ mii mint Acme::Anvil --author=John Smith --license=perl_5 --license=artistic_2' => sub {
        my $outdir = tempdir();
        my ( $stdout, $stderr, $exit ) = run_mii( $outdir, qw[mint Acme::Anvil], '--author=John Smith', '--license=perl_5', '--license=artistic_2' );
        is $exit, 0, 'exit ok';
        diag $stdout;
        diag $stderr;
        $outdir->visit( sub { diag $_->realpath }, { recurse => 1 } );
        diag $outdir->child( 'Acme-Anvil', 'mii.conf' )->slurp;
        like $outdir->child( 'Acme-Anvil', 'LICENSE' )->slurp, qr[The Artistic License 2.0],                      'artistic_2 license found';
        like $outdir->child( 'Acme-Anvil', 'LICENSE' )->slurp, qr[same terms as the Perl 5 programming language], 'perl_5 license found';

        #~ like $stdout, qr[requires a package], 'missing package name';
    };
    {
        my $outdir = tempdir();
        subtest '$ mii mint Acme::Anvil --license=perl_5 --author=John Smith' => sub {
            my ( $stdout, $stderr, $exit ) = run_mii( $outdir, qw[mint Acme::Anvil --license=perl_5], '--author=John Smith' );
            is $exit, 0, 'exit ok';
            diag $stdout;
            diag $stderr;
            $outdir->visit( sub { diag $_->realpath }, { recurse => 1 } );
            like $outdir->child( 'Acme-Anvil', 'LICENSE' )->slurp, qr[same terms as the Perl 5 programming language], 'proper license file';

            #~ like $stdout, qr[requires a package], 'missing package name';
        };
        subtest '$ mii list' => sub {

            #~ my ( $stdout, $stderr, $exit ) = run_mii( $outdir, qw[mint list] );
            #~ is $exit, 0, 'exit ok';
            #~ diag $stdout;
            #~ diag $stderr;
            $outdir->visit( sub { diag $_->realpath }, { recurse => 1 } );
            ok 1;

            #~ like $stdout, qr[requires a package], 'missing package name';
        };
    };
};

sub run_mii ( $dir, @args ) {
    diag qq[working in $dir];
    chdir $dir->canonpath;
    my ( $stdout, $stderr, $errno ) = capture {
        system( $^X, '-I' . $cwd->child('../lib')->canonpath, $mii_pl, @args )
    };
    chdir $cwd->canonpath;
    ( $stdout, $stderr, $errno );
}
done_testing;
