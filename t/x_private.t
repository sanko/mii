use v5.38;
use Test2::V0;
use Capture::Tiny qw[capture];
use Path::Tiny    qw[path tempdir];
use JSON::PP;

# Setup environment
my $cwd    = path('.')->realpath;
my $mii_pl = $cwd->child( 'script', 'mii.pl' )->realpath;
$mii_pl = $cwd->child( 'script', 'mii' )->realpath unless $mii_pl->exists;

sub run_mii ( $dir, @args ) {
    my $prev_cwd = path('.')->realpath;
    chdir $dir->canonpath;
    my ( $stdout, $stderr, $errno ) = capture {
        system( $^X, '-I' . $cwd->child('lib')->canonpath, $mii_pl, @args )
    };
    chdir $prev_cwd->canonpath;
    ( $stdout, $stderr, $errno );
}
subtest 'x_private' => sub {
    my $dir = tempdir();
    $dir->child('lib')->mkpath;
    $dir->child('lib/Foo.pm')->spew("package Foo; 1;");
    $dir->child('Changes.md')->spew("# Changelog\n\n## [Unreleased]\n\n- Initial\n");
    my $meta = { name => 'Foo', version => '0.01', abstract => 'test', author => ['Me'], license => ['perl_5'], x_private => 1, };
    $dir->child('META.json')->spew( encode_json($meta) );

    # We need to be in a git repo for release to work
    system("git init $dir");
    {
        my $prev_cwd = path('.')->realpath;
        chdir $dir;
        system('git config user.email "you@example.com"');
        system('git config user.name "Your Name"');
        system("git add .");
        system('git commit -m initial');
        chdir $prev_cwd;
    }
    my ( $stdout, $stderr, $exit ) = run_mii $dir, 'release';
    like $stdout, qr/Blocking release of private distribution/, 'Blocked release with x_private';
};
subtest 'x_no_upload' => sub {
    my $dir = tempdir();
    $dir->child('lib')->mkpath;
    $dir->child('lib/Foo.pm')->spew("package Foo; 1;");
    $dir->child('Changes.md')->spew("# Changelog\n\n## [Unreleased]\n\n- Initial\n");
    my $meta = { name => 'Foo', version => '0.01', abstract => 'test', author => ['Me'], license => ['perl_5'], x_no_upload => 1, };
    $dir->child('META.json')->spew( encode_json($meta) );
    system("git init $dir");
    {
        my $prev_cwd = path('.')->realpath;
        chdir $dir;
        system('git config user.email "you@example.com"');
        system('git config user.name "Your Name"');
        system("git add .");
        system('git commit -m initial');
        chdir $prev_cwd;
    }
    my ( $stdout, $stderr, $exit ) = run_mii $dir, 'release';
    like $stdout, qr/Blocking release of private distribution/, 'Blocked release with x_no_upload';
};
done_testing;
