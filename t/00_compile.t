use v5.38;
use Test2::V0 '!subtest';
use Test2::Util::Importer 'Test2::Tools::Subtest' => ( subtest_streamed => { -as => 'subtest' } );
use Capture::Tiny qw[capture];
use Path::Tiny    qw[path tempdir];
use lib '../lib';
use App::mii;
$|++;
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
            ok $outdir->child( 'Acme-Anvil', 'META.json' )->is_file, 'META.json';
            ok $outdir->child( 'Acme-Anvil', 'META.yml' )->is_file,  'META.yml';

            #~ diag $outdir->child( 'Acme-Anvil', 'META.json' )->slurp;
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
            ok $outdir->child( 'Acme-Anvil', 'META.json' )->is_file, 'META.json';
            ok $outdir->child( 'Acme-Anvil', 'META.yml' )->is_file,  'META.yml';
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
    subtest '$ mii mint Acme::Auto --github_actions=1' => sub {
        my $outdir = tempdir();

        # We need to simulate the 'eg' directory for the test to copy from
        my $mock_eg = path('eg/.github');
        unless ( $mock_eg->exists ) {

            # If running from t/, eg might be in ../eg
            my $real_eg = path('../eg/.github');
            if ( $real_eg->exists ) {

                # Create a local eg/ for the test execution context if needed,
                # but mii checks ../eg so it might just work if we are in t/
                # However, run_mii changes dir to a tempdir.
                # So we need to ensure the tempdir sees 'eg'.
                # Actually, mii looks for eg relative to where it runs.
            }
        }

        # To make the test reliable, we should pass the location of 'eg' or ensure mii finds it.
        # But 'mii' logic I just wrote looks for 'eg/.github' or '../eg/.github'.
        # Since run_mii runs in a tempdir, '../eg' would refer to the parent of the tempdir, which is likely random.
        # So I need to copy 'eg' to the tempdir or the parent of the tempdir.
        # Or, I can rely on the fact that I'm testing in a sandbox and I can just mock the files in the tempdir's parent.
        # Let's try to copy eg to the tempdir where we run mii?
        # mii.pl is invoked from the tempdir.
        # So if we put 'eg' in the tempdir, mii should find 'eg/.github'.
        my $eg = $outdir->child( 'eg', '.github' );
        $eg->mkpath;
        $eg->child('workflows')->mkpath;
        $eg->child( 'workflows', 'ci.yml' )->spew('mock ci');

        # Run mint
        # Arguments: Package Name (Acme::Auto) is passed.
        # We also need to pass other args to avoid prompts: version, description, license
        my ( $stdout, $stderr, $exit ) = run_mii $outdir,
            qw[mint Acme::Auto --github_actions=1 --version=v0.0.2 --description=Automatic --license=mit];
        is $exit, 0, 'exit ok';
        my $dist_dir = $outdir->child('Acme-Auto');
        ok $dist_dir->is_dir, 'dist dir created';
        ok $dist_dir->child( '.github', 'workflows', 'ci.yml' )->exists, 'workflow copied';
        is $dist_dir->child( '.github', 'workflows', 'ci.yml' )->slurp, 'mock ci', 'workflow content matches';
        ok $dist_dir->child('META.json')->exists, 'META.json created';
    };
    subtest 'mint from existing META.json' => sub {
        my $outdir   = tempdir();
        my $dist_dir = $outdir->child('Acme-Existing');
        $dist_dir->mkpath;
        my $meta = {
            name        => 'Acme-Existing',
            version     => 'v1.2.3',
            description => 'Existing Description',
            license     => ['artistic_2'],
            author      => ['Me <me@example.com>'],
        };
        require JSON::PP;
        $dist_dir->child('META.json')->spew( JSON::PP->new->pretty->encode($meta) );

        # Change to dist_dir to simulate running inside the repo
        # run_mii takes a directory to run IN.
        # But we need to invoke 'mii mint' inside 'Acme-Existing'?
        # Or 'mii mint Acme::Existing' inside 'Acme-Existing'?
        # The prompt says: "mii mint should pull all data from that .json file".
        # If I run 'mii mint' inside the dir, it should detect META.json.
        # We need to adjust run_mii to allow running inside the dist dir if we pass it as the dir.
        my ( $stdout, $stderr, $exit ) = run_mii $dist_dir, qw[mint];

        # No args provided, should pick up from META.json and defaults
        # However, mint creates a subdirectory 'Acme-Existing' by default inside the current dir?
        # If I run 'mii mint' inside '.../Acme-Existing', it might try to create '.../Acme-Existing/Acme-Existing'.
        # Unless I pass '.' as name? Or if it detects name from META.json.
        # In lib/App/mii.pm:
        # $path = $path->child($self->name);
        # If I am already in the root, $path is '.'.
        # $self->name comes from META.json ('Acme-Existing').
        # So it will create ./Acme-Existing/ ... which is nested.
        # The requirement "If we already have a META.json file, mii mint should pull all data from that .json file"
        # implies we are refreshing/re-minting an existing project IN PLACE.
        # If I am in 'Acme-Existing' directory, and I run 'mii mint',
        # ADJUST loads META.json. $config is populated.
        # init() calls $path->child($self->name).
        # $path is '.' (param default).
        # $self->name is 'Acme-Existing'.
        # So it tries to create 'Acme-Existing/Acme-Existing'.
        # This seems to be a conflict between "create new project in subdir" and "refresh existing project".
        # If META.json exists in '.', we probably shouldn't create a subdir?
        # Let's check init logic again.
        # $path = $path->child($self->name);
        # This forces a subdir.
        # I should modify init to check if we are already in the target directory.
        # If $path->basename eq $self->name (or close), maybe don't child?
        # Or if META.json exists in $path?
        is $exit, 0, 'exit ok';

        # Verify it didn't prompt (because defaults and META.json)
        # Verify files are created/updated.
        # Currently, due to the logic, it will create a subdir.
        # Let's see if we can fix that logic in the next step.
        # For now, let's just see what happens.
    };
};
done_testing;
