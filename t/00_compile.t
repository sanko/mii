use v5.38;
use Test2::V0;
use Capture::Tiny qw[capture];
use Path::Tiny    qw[path tempdir];
use lib '../lib';
use App::mii;
diag 'App::mii ' . $App::mii::VERSION;
my ($mii_pl) = map { $_->realpath } grep { $_->exists } map { path(qq[$_/script/mii]); } '.', '..';
#
my $cwd = path('.')->realpath;

sub run_mii ( $dir, @args ) {
    diag qq[working in $dir];
    chdir $dir->canonpath;
    my ( $stdout, $stderr, $errno ) = capture {
        system( $^X, '-I' . $cwd->child('../lib')->canonpath, $mii_pl, @args )
    };
    chdir $cwd->canonpath;
    ( $stdout, $stderr, $errno );
}
subtest live => sub {
    $mii_pl // skip_all 'failed to locate mii.pl';
    diag qq[found mii.pl at $mii_pl];
    subtest '$ mii' => sub {
        my ( $stdout, $stderr, $exit ) = run_mii tempdir;
        is $exit, 0, 'exit ok';
        like $stdout, qr[Usage], 'usage';
    };
    subtest '$ mii help' => sub {
        my ( $stdout, $stderr, $exit ) = run_mii tempdir, 'help';
        is $exit, 0, 'exit ok';
        like $stdout, qr[Usage], 'usage';
    };
    subtest '$ mii mint' => sub {
        my ( $stdout, $stderr, $exit ) = run_mii tempdir, 'mint';
        isnt $exit, 0, ' exit error ';
        like $stdout, qr[requires a package], ' missing package name';
    };
    subtest '$ mii mint Acme::Anvil --author=John Smith' => sub {
        my $outdir = tempdir();
        my ( $stdout, $stderr, $exit ) = run_mii $outdir, qw[mint Acme::Anvil], '--author=John Smith';
        is $exit, 0, 'exit ok';
        diag $stdout if $stdout;
        diag $stderr if $stderr;

        #~ $outdir->visit( sub { diag $_->realpath }, { recurse => 1 } );
        subtest files => sub {
            ok $outdir->child( 'Acme-Anvil', 'mii.conf' )->is_file, 'mii.conf';

            #~ diag $outdir->child( 'Acme-Anvil', 'mii.conf' )->slurp;
            subtest LICENSE => sub {
                ok $outdir->child( 'Acme-Anvil', 'LICENSE' )->is_file, 'LICENSE';
                like $outdir->child( 'Acme-Anvil', 'LICENSE' )->slurp, qr[The Artistic License 2.0], 'Artistic License 2.0';
            };
            ok $outdir->child( 'Acme-Anvil', 'Build.PL' )->is_file, 'Build.PL';
        }

        #~ like $stdout, qr[requires a package], 'missing package name';
    };
    subtest '$ mii mint Acme::Anvil --author=John Smith --license=perl_5 --license=artistic_2' => sub {
        my $outdir = tempdir();
        my ( $stdout, $stderr, $exit ) = run_mii $outdir, qw[mint Acme::Anvil], '--author=John Smith', '--license=perl_5', '--license=artistic_2';
        is $exit, 0, 'exit ok';
        diag $stdout if $stdout;
        diag $stderr if $stderr;

        #~ $outdir->visit( sub { diag $_->realpath }, { recurse => 1 } );
        subtest files => sub {
            ok $outdir->child( 'Acme-Anvil', 'mii.conf' )->is_file, 'mii.conf';
            subtest LICENSE => sub {
                my $license = $outdir->child( 'Acme-Anvil', 'LICENSE' );
                ok $license->is_file, 'LICENSE';
                like $license->slurp, qr[The Artistic License 2.0],                      'Artistic License 2.0';
                like $license->slurp, qr[same terms as the Perl 5 programming language], 'Perl 5 license';
            };
            ok $outdir->child( 'Acme-Anvil', 'Build.PL' )->is_file, 'Build.PL';
        }
    };
    {
        my $outdir = tempdir();
        subtest '$ mii mint Acme::Anvil --license=perl_5 --author=John Smith' => sub {
            my ( $stdout, $stderr, $exit ) = run_mii $outdir, qw[mint Acme::Anvil --license=perl_5], '--author=John Smith';
            is $exit, 0, 'exit ok';
            diag $stdout if $stdout;
            diag $stderr if $stderr;

            #~ $outdir->visit( sub { diag $_->realpath }, { recurse => 1 } );
            like $outdir->child( 'Acme-Anvil', 'LICENSE' )->slurp, qr[same terms as the Perl 5 programming language], 'proper license file';
            ( $stdout, $stderr, $exit ) = run_mii $outdir->child('Acme-Anvil'), qw[dist];
            diag $stdout if $stdout;
            diag $stderr if $stderr;
            #
            ( $stdout, $stderr, $exit ) = run_mii $outdir->child('Acme-Anvil'), qw[list];
            diag $stdout if $stdout;
            diag $stderr if $stderr;

            #~ like $stdout, qr[requires a package], 'missing package name';
        };
        subtest '$ mii dist' => sub {
            my ( $stdout, $stderr, $exit ) = run_mii $outdir->child('Acme-Anvil'), qw[dist];
            is $exit, 0, 'exit ok';

            #~ diag $stdout if $stdout;
            diag $stderr if $stderr;
            ok $outdir->child( 'Acme-Anvil', 'Acme-Anvil-v0.0.1.tar.gz' )->is_file, '.tar.gz';

            #~ $outdir->visit( sub { diag $_->realpath }, { recurse => 1 } );
            #~ like $stdout, qr[requires a package], 'missing package name';
        };

        # TODO: share
    };
};
done_testing;
