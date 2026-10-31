package App::mii::Plugin::GitHubActions;
use v5.38;
use feature 'class';
no warnings 'experimental::class';

class App::mii::Plugin::GitHubActions {
    use Path::Tiny qw[path];

    method after_init( $app, @args ) {
        my $target_github = $app->path->child('.github');
        $target_github->mkdir;
        my $workflows = $self->templates;
        for my $file ( keys %$workflows ) {
            my $content = $workflows->{$file};
            my $dest    = $target_github->child($file);
            $dest->parent->mkpath;
            $dest->spew_utf8($content);
        }
        $app->log("Generated GitHub Actions workflows");
    }

    method templates() {
        return {
            'FUNDING.yml' => <<'END',
# These are supported funding model platforms

github: sanko # Replace with up to 4 GitHub Sponsors-enabled usernames e.g., [user1, user2]
patreon: # Replace with a single Patreon username
open_collective: # Replace with a single Open Collective username
ko_fi: # Replace with a single Ko-fi username
tidelift: # Replace with a single Tidelift platform-name/package-name e.g., npm/babel
community_bridge: # Replace with a single Community Bridge project-name e.g., cloud-foundry
liberapay: # Replace with a single Liberapay username
issuehunt: # Replace with a single IssueHunt username
otechie: # Replace with a single Otechie username
custom: # Replace with up to 4 custom sponsorship URLs e.g., ['link1', 'link2']
END
            'workflows/ci.yml' => <<'END',
---
name: CI Matrix
on:
  pull_request: ~
  push: ~
  schedule:
    - cron: 42 5 * * 0
  workflow_dispatch: ~
permissions:
  actions: read
  contents: read

jobs:
  freebsd:
    name: FreeBSD
    uses: sanko/workflow-testing/.github/workflows/run-vm.yml@main
    with:
      os_version: '14.1'
      checkout_submodules: 'recursive'
      task: |
        export AUTOMATED_TESTING=1 AUTHOR_TESTING=0
        #~ Bootstrap cpanm via a file download, never `curl | perl`: some remote
        #~ sh's run under pipefail, and curl's EPIPE (23) after a clean pipe
        #~ install aborts the whole run even though it succeeded. cpanm lands in
        #~ the active perl's sitebin/scriptdir, which is not on PATH everywhere,
        #~ so re-export those dirs after bootstrapping.
        curl -fsSL https://cpanmin.us -o /tmp/cpanmin.pl
        perl /tmp/cpanmin.pl --notest App::cpanminus Module::Build::Tiny
        rm -f /tmp/cpanmin.pl
        export PATH="$(dirname "$(perl -e 'print $^X')"):$(perl -MConfig -e 'print "$Config{sitebin}:$Config{scriptdir}:"' 2>/dev/null):$PATH"
        command -v cpanm
        cpanm --installdeps --notest -v .
        cpanm --test-only -v .
      matrix: >-
        [
          {"platform_name":"freebsd","os":"freebsd","arch":"x86_64","toolchain":"gcc","prepare":"pkg install -y perl5 curl"},
          {"platform_name":"freebsd","os":"freebsd","arch":"aarch64","toolchain":"gcc","prepare":"pkg install -y perl5 curl"}
        ]

  linux:
    name: Linux
    uses: sanko/workflow-testing/.github/workflows/run-direct.yml@main
    with:
      checkout_submodules: 'recursive'
      task: |
        export AUTOMATED_TESTING=1 AUTHOR_TESTING=1
        #~ Bootstrap cpanm via its canonical one-liner; on a writable perl (a
        #~ source build) it lands in the perl's own bin dir, which the runner
        #~ puts on PATH. Distro perl is read-only to the runner user, so
        #~ cpanm relocates every install into $HOME/perl5 instead. Adopt that
        #~ layout (PATH + local::lib env) so cpanm deps and the Build steps
        #~ share one module pool. No-op when $HOME/perl5 was never created.
        curl -L https://cpanmin.us | perl - --notest App::cpanminus
        if [ -x "$HOME/perl5/bin/cpanm" ]; then
          export PATH="$HOME/perl5/bin:$PATH"
          "$HOME/perl5/bin/cpanm" --local-lib="$HOME/perl5" --notest local::lib
          eval "$(perl -I "$HOME/perl5/lib/perl5" -Mlocal::lib)"
        fi
        command -v cpanm
        cpanm --installdeps --notest --with-suggests --with-recommends --with-configure -v .
        perl Build.PL
        ./Build
        ./Build test --v
      matrix: >-
        [
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","variant":"default","platform_name":"linux","os":"ubuntu-26.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.40.2","configure":"-Dusethreads","variant":"threads","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.40.2","configure":"-Duselongdouble","variant":"longdouble","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.40.2","configure":"-Dusequadmath","variant":"quadmath","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.40.2","configure":"-DDEBUGGING","variant":"debug","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.40.2","configure":"-DDEBUGGING=both","variant":"debugging","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.40.2","configure":"-DDEBUGGING=-g","variant":"debugging-g","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.40.2","configure":"-Doptimize=-g","variant":"optimize-g","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.40.2","configure":"-DDEBUGGING=none","variant":"debugging-none","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.40.2","configure":"-UDEBUGGING","variant":"nodebugging","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.40.2","configure":"-Dusethreads -DDEBUGGING=both","variant":"threads-debugging","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.40.2","configure":"-Dusethreads -Duselongdouble -DDEBUGGING=both","variant":"threads-longdouble-debugging","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.40.2","configure":"-Dusethreads -Dusequadmath -DDEBUGGING=both","variant":"threads-quadmath-debugging","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.42.0","variant":"default","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.42.0","configure":"-Dusethreads","variant":"threads","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.42.0","configure":"-Duselongdouble","variant":"longdouble","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.42.0","configure":"-Dusequadmath","variant":"quadmath","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.42.0","configure":"-DDEBUGGING","variant":"debug","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.42.0","configure":"-DDEBUGGING=both","variant":"debugging","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.42.0","configure":"-DDEBUGGING=-g","variant":"debugging-g","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.42.0","configure":"-Doptimize=-g","variant":"optimize-g","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.42.0","configure":"-DDEBUGGING=none","variant":"debugging-none","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.42.0","configure":"-UDEBUGGING","variant":"nodebugging","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.42.0","configure":"-Dusethreads -DDEBUGGING=both","variant":"threads-debugging","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.42.0","configure":"-Dusethreads -Duselongdouble -DDEBUGGING=both","variant":"threads-longdouble-debugging","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.42.0","configure":"-Dusethreads -Dusequadmath -DDEBUGGING=both","variant":"threads-quadmath-debugging","platform_name":"linux","os":"ubuntu-24.04","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind clang build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.40.2","configure":"-Dcc=clang","platform_name":"linux","os":"ubuntu-24.04","toolchain":"clang"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind clang build-essential libperl-dev libcrypt-dev","arch":"x86_64","perl_version":"5.42.0","configure":"-Dcc=clang","platform_name":"linux","os":"ubuntu-24.04","toolchain":"clang"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"aarch64","variant":"default","platform_name":"linux","os":"ubuntu-26.04-arm","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"aarch64","perl_version":"5.40.2","configure":"-Dusethreads","variant":"threads","platform_name":"linux","os":"ubuntu-24.04-arm","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","arch":"aarch64","perl_version":"5.42.0","variant":"default","platform_name":"linux","os":"ubuntu-24.04-arm","toolchain":"gcc"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind clang build-essential libperl-dev libcrypt-dev","arch":"aarch64","perl_version":"5.42.0","configure":"-Dcc=clang","platform_name":"linux","os":"ubuntu-24.04-arm","toolchain":"clang"},
          {"prepare":"sudo apt-get update -y && sudo apt-get install -y valgrind build-essential libperl-dev libcrypt-dev","platform_name":"riscv","os":"ubuntu-26.04-riscv","arch":"riscv64","toolchain":"gcc","variant":"default"}
        ]

  macos:
    name: macOS
    uses: sanko/workflow-testing/.github/workflows/run-direct.yml@main
    with:
      checkout_submodules: 'recursive'
      task: |
        export AUTOMATED_TESTING=1 AUTHOR_TESTING=1
        #~ Bootstrap cpanm via its canonical one-liner; it installs into the
        #~ active (source-built) perl's bin dir, which the runner puts on PATH.
        curl -L https://cpanmin.us | perl - --notest App::cpanminus
        command -v cpanm
        cpanm --installdeps --notest --with-suggests --with-recommends --with-configure -v .
        perl Build.PL
        ./Build
        ./Build test --v
      matrix: >-
        [
          {"arch":"aarch64","perl_version":"5.40.2","variant":"default","platform_name":"macos","os":"macos-15","toolchain":"clang"},
          {"arch":"aarch64","perl_version":"5.40.2","configure":"-Duselongdouble","variant":"longdouble","platform_name":"macos","os":"macos-15","toolchain":"clang"},
          {"arch":"aarch64","perl_version":"5.40.2","configure":"-DDEBUGGING","variant":"debug","platform_name":"macos","os":"macos-15","toolchain":"clang"},
          {"arch":"aarch64","perl_version":"5.40.2","configure":"-DDEBUGGING=both","variant":"debugging","platform_name":"macos","os":"macos-15","toolchain":"clang"},
          {"arch":"aarch64","perl_version":"5.40.2","configure":"-DDEBUGGING=-g","variant":"debugging-g","platform_name":"macos","os":"macos-15","toolchain":"clang"},
          {"arch":"aarch64","perl_version":"5.40.2","configure":"-Doptimize=-g","variant":"optimize-g","platform_name":"macos","os":"macos-15","toolchain":"clang"},
          {"arch":"aarch64","perl_version":"5.40.2","configure":"-DDEBUGGING=none","variant":"debugging-none","platform_name":"macos","os":"macos-15","toolchain":"clang"},
          {"arch":"aarch64","perl_version":"5.40.2","configure":"-UDEBUGGING","variant":"nodebugging","platform_name":"macos","os":"macos-15","toolchain":"clang"},
          {"arch":"aarch64","perl_version":"5.42.0","variant":"default","platform_name":"macos","os":"macos-15","toolchain":"clang"},
          {"arch":"aarch64","perl_version":"5.42.0","configure":"-Duselongdouble","variant":"longdouble","platform_name":"macos","os":"macos-15","toolchain":"clang"},
          {"arch":"aarch64","perl_version":"5.42.0","configure":"-DDEBUGGING","variant":"debug","platform_name":"macos","os":"macos-15","toolchain":"clang"},
          {"arch":"aarch64","perl_version":"5.42.0","configure":"-DDEBUGGING=both","variant":"debugging","platform_name":"macos","os":"macos-15","toolchain":"clang"},
          {"arch":"aarch64","perl_version":"5.42.0","configure":"-DDEBUGGING=-g","variant":"debugging-g","platform_name":"macos","os":"macos-15","toolchain":"clang"},
          {"arch":"aarch64","perl_version":"5.42.0","configure":"-Doptimize=-g","variant":"optimize-g","platform_name":"macos","os":"macos-15","toolchain":"clang"},
          {"arch":"aarch64","perl_version":"5.42.0","configure":"-DDEBUGGING=none","variant":"debugging-none","platform_name":"macos","os":"macos-15","toolchain":"clang"},
          {"arch":"aarch64","perl_version":"5.42.0","configure":"-UDEBUGGING","variant":"nodebugging","platform_name":"macos","os":"macos-15","toolchain":"clang"},
          {"arch":"x86_64","perl_version":"5.40.2","variant":"default","platform_name":"macos","os":"macos-15-intel","toolchain":"clang"},
          {"arch":"x86_64","perl_version":"5.40.2","configure":"-Duselongdouble","variant":"longdouble","platform_name":"macos","os":"macos-15-intel","toolchain":"clang"},
          {"arch":"x86_64","perl_version":"5.40.2","configure":"-DDEBUGGING","variant":"debug","platform_name":"macos","os":"macos-15-intel","toolchain":"clang"},
          {"arch":"x86_64","perl_version":"5.40.2","configure":"-DDEBUGGING=both","variant":"debugging","platform_name":"macos","os":"macos-15-intel","toolchain":"clang"},
          {"arch":"x86_64","perl_version":"5.40.2","configure":"-DDEBUGGING=-g","variant":"debugging-g","platform_name":"macos","os":"macos-15-intel","toolchain":"clang"},
          {"arch":"x86_64","perl_version":"5.40.2","configure":"-Doptimize=-g","variant":"optimize-g","platform_name":"macos","os":"macos-15-intel","toolchain":"clang"},
          {"arch":"x86_64","perl_version":"5.40.2","configure":"-DDEBUGGING=none","variant":"debugging-none","platform_name":"macos","os":"macos-15-intel","toolchain":"clang"},
          {"arch":"x86_64","perl_version":"5.40.2","configure":"-UDEBUGGING","variant":"nodebugging","platform_name":"macos","os":"macos-15-intel","toolchain":"clang"},
          {"arch":"x86_64","perl_version":"5.42.0","variant":"default","platform_name":"macos","os":"macos-15-intel","toolchain":"clang"},
          {"arch":"x86_64","perl_version":"5.42.0","configure":"-Duselongdouble","variant":"longdouble","platform_name":"macos","os":"macos-15-intel","toolchain":"clang"},
          {"arch":"x86_64","perl_version":"5.42.0","configure":"-DDEBUGGING","variant":"debug","platform_name":"macos","os":"macos-15-intel","toolchain":"clang"},
          {"arch":"x86_64","perl_version":"5.42.0","configure":"-DDEBUGGING=both","variant":"debugging","platform_name":"macos","os":"macos-15-intel","toolchain":"clang"},
          {"arch":"x86_64","perl_version":"5.42.0","configure":"-DDEBUGGING=-g","variant":"debugging-g","platform_name":"macos","os":"macos-15-intel","toolchain":"clang"},
          {"arch":"x86_64","perl_version":"5.42.0","configure":"-Doptimize=-g","variant":"optimize-g","platform_name":"macos","os":"macos-15-intel","toolchain":"clang"},
          {"arch":"x86_64","perl_version":"5.42.0","configure":"-DDEBUGGING=none","variant":"debugging-none","platform_name":"macos","os":"macos-15-intel","toolchain":"clang"},
          {"arch":"x86_64","perl_version":"5.42.0","configure":"-UDEBUGGING","variant":"nodebugging","platform_name":"macos","os":"macos-15-intel","toolchain":"clang"}
        ]

  openbsd:
    name: OpenBSD
    uses: sanko/workflow-testing/.github/workflows/run-vm.yml@main
    with:
      os_version: '7.8'
      checkout_submodules: 'recursive'
      task: |
        export AUTOMATED_TESTING=1 AUTHOR_TESTING=0
        #~ Bootstrap cpanm via a file download, never `curl | perl`: some remote
        #~ sh's run under pipefail, and curl's EPIPE (23) after a clean pipe
        #~ install aborts the whole run even though it succeeded. cpanm lands in
        #~ the active perl's sitebin/scriptdir, which is not on PATH everywhere,
        #~ so re-export those dirs after bootstrapping.
        if command -v curl >/dev/null 2>&1; then curl -fsSL https://cpanmin.us -o /tmp/cpanmin.pl
        elif command -v wget >/dev/null 2>&1; then wget -qO /tmp/cpanmin.pl https://cpanmin.us
        elif command -v fetch >/dev/null 2>&1; then fetch -o /tmp/cpanmin.pl https://cpanmin.us
        else echo 'no http downloader available' >&2; exit 1; fi
        perl /tmp/cpanmin.pl --notest App::cpanminus Module::Build::Tiny
        rm -f /tmp/cpanmin.pl
        export PATH="$(dirname "$(perl -e 'print $^X')"):$(perl -MConfig -e 'print "$Config{sitebin}:$Config{scriptdir}:"' 2>/dev/null):$PATH"
        command -v cpanm
        cpanm --installdeps --notest -v .
        cpanm --test-only -v .
      matrix: >-
        [
          {"platform_name":"openbsd","os":"openbsd","arch":"x86_64","toolchain":"gcc","perl_version":"5.40.2","prepare":"pkg_add gmake curl"},
          {"platform_name":"openbsd","os":"openbsd","arch":"x86_64","toolchain":"clang","perl_version":"5.40.2","configure":"-Dcc=clang","prepare":"pkg_add gmake curl"}
        ]

  netbsd:
    name: NetBSD
    uses: sanko/workflow-testing/.github/workflows/run-vm.yml@main
    with:
      os_version: '11.0'
      checkout_submodules: 'recursive'
      task: |
        export AUTOMATED_TESTING=1 AUTHOR_TESTING=0
        #~ Bootstrap cpanm via a file download, never `curl | perl`: some remote
        #~ sh's run under pipefail, and curl's EPIPE (23) after a clean pipe
        #~ install aborts the whole run even though it succeeded. cpanm lands in
        #~ the active perl's sitebin/scriptdir, which is not on PATH everywhere,
        #~ so re-export those dirs after bootstrapping.
        if command -v curl >/dev/null 2>&1; then curl -fsSL https://cpanmin.us -o /tmp/cpanmin.pl
        elif command -v wget >/dev/null 2>&1; then wget -qO /tmp/cpanmin.pl https://cpanmin.us
        elif command -v fetch >/dev/null 2>&1; then fetch -o /tmp/cpanmin.pl https://cpanmin.us
        else echo 'no http downloader available' >&2; exit 1; fi
        perl /tmp/cpanmin.pl --notest App::cpanminus Module::Build::Tiny
        rm -f /tmp/cpanmin.pl
        export PATH="$(dirname "$(perl -e 'print $^X')"):$(perl -MConfig -e 'print "$Config{sitebin}:$Config{scriptdir}:"' 2>/dev/null):$PATH"
        command -v cpanm
        cpanm --installdeps --notest -v .
        cpanm --test-only -v .
      matrix: >-
        [
          {"platform_name":"netbsd","os":"netbsd","arch":"x86_64","toolchain":"gcc","perl_version":"5.42.3","prepare":"/usr/sbin/pkg_add perl curl gmake"},
          {"platform_name":"netbsd","os":"netbsd","arch":"aarch64","toolchain":"gcc","prepare":"/usr/sbin/pkg_add perl curl gmake"},
          {"platform_name":"netbsd","os":"netbsd","arch":"riscv64","toolchain":"gcc","prepare":"/usr/sbin/pkg_add perl curl gmake"}
        ]

  dragonflybsd:
    name: DragonFly BSD
    uses: sanko/workflow-testing/.github/workflows/run-vm.yml@main
    with:
      os_version: '6.4.0'
      checkout_submodules: 'recursive'
      task: |
        export AUTOMATED_TESTING=1 AUTHOR_TESTING=0
        #~ Bootstrap cpanm via a file download, never `curl | perl`: some remote
        #~ sh's run under pipefail, and curl's EPIPE (23) after a clean pipe
        #~ install aborts the whole run even though it succeeded. cpanm lands in
        #~ the active perl's sitebin/scriptdir, which is not on PATH everywhere,
        #~ so re-export those dirs after bootstrapping.
        if command -v curl >/dev/null 2>&1; then curl -fsSL https://cpanmin.us -o /tmp/cpanmin.pl
        elif command -v wget >/dev/null 2>&1; then wget -qO /tmp/cpanmin.pl https://cpanmin.us
        elif command -v fetch >/dev/null 2>&1; then fetch -o /tmp/cpanmin.pl https://cpanmin.us
        else echo 'no http downloader available' >&2; exit 1; fi
        perl /tmp/cpanmin.pl --notest App::cpanminus Module::Build::Tiny
        rm -f /tmp/cpanmin.pl
        export PATH="$(dirname "$(perl -e 'print $^X')"):$(perl -MConfig -e 'print "$Config{sitebin}:$Config{scriptdir}:"' 2>/dev/null):$PATH"
        command -v cpanm
        cpanm --installdeps --notest -v .
        cpanm --test-only -v .
      matrix: >-
        [
          {"platform_name":"dragonflybsd","os":"dragonflybsd","arch":"x86_64","toolchain":"gcc","perl_version":"5.40.2","prepare":"pkg update && pkg upgrade -y && pkg install -y perl5 gcc gmake curl"}
        ]

  solaris:
    name: Solaris
    uses: sanko/workflow-testing/.github/workflows/run-vm.yml@main
    with:
      os_version: '11.4'
      checkout_submodules: 'recursive'
      task: |
        export AUTOMATED_TESTING=1 AUTHOR_TESTING=0
        #~ Bootstrap cpanm via a file download, never `curl | perl`: some remote
        #~ sh's run under pipefail, and curl's EPIPE (23) after a clean pipe
        #~ install aborts the whole run even though it succeeded. cpanm lands in
        #~ the active perl's sitebin/scriptdir, which is not on PATH everywhere,
        #~ so re-export those dirs after bootstrapping.
        if command -v curl >/dev/null 2>&1; then curl -fsSL https://cpanmin.us -o /tmp/cpanmin.pl
        elif command -v wget >/dev/null 2>&1; then wget -qO /tmp/cpanmin.pl https://cpanmin.us
        elif command -v fetch >/dev/null 2>&1; then fetch -o /tmp/cpanmin.pl https://cpanmin.us
        else echo 'no http downloader available' >&2; exit 1; fi
        perl /tmp/cpanmin.pl --notest App::cpanminus Module::Build::Tiny
        rm -f /tmp/cpanmin.pl
        export PATH="$(dirname "$(perl -e 'print $^X')"):$(perl -MConfig -e 'print "$Config{sitebin}:$Config{scriptdir}:"' 2>/dev/null):$PATH"
        command -v cpanm
        cpanm --installdeps --notest -v .
        cpanm --test-only -v .
      matrix: >-
        [
          {"platform_name":"solaris","os":"solaris","arch":"x86_64","toolchain":"gcc","perl_version":"5.40.2","variant":"stock","prepare":"pkg install -v --accept perl-538 gcc developer/build/make bash web/curl"},
          {"platform_name":"solaris","os":"solaris","arch":"x86_64","toolchain":"gcc","perl_version":"5.40.2","configure":"-A'ccflags=-D__EXTENSIONS__'","variant":"configured-extensions","prepare":"pkg install -v --accept perl-538 gcc developer/build/make bash web/curl"}
        ]

  omnios:
    name: OmniOS
    uses: sanko/workflow-testing/.github/workflows/run-vm.yml@main
    with:
      os_version: 'r151050'
      checkout_submodules: 'recursive'
      task: |
        export AUTOMATED_TESTING=1 AUTHOR_TESTING=0
        #~ Bootstrap cpanm via a file download, never `curl | perl`: some remote
        #~ sh's run under pipefail, and curl's EPIPE (23) after a clean pipe
        #~ install aborts the whole run even though it succeeded. cpanm lands in
        #~ the active perl's sitebin/scriptdir, which is not on PATH everywhere,
        #~ so re-export those dirs after bootstrapping.
        if command -v curl >/dev/null 2>&1; then curl -fsSL https://cpanmin.us -o /tmp/cpanmin.pl
        elif command -v wget >/dev/null 2>&1; then wget -qO /tmp/cpanmin.pl https://cpanmin.us
        elif command -v fetch >/dev/null 2>&1; then fetch -o /tmp/cpanmin.pl https://cpanmin.us
        else echo 'no http downloader available' >&2; exit 1; fi
        perl /tmp/cpanmin.pl --notest App::cpanminus Module::Build::Tiny
        rm -f /tmp/cpanmin.pl
        export PATH="$(dirname "$(perl -e 'print $^X')"):$(perl -MConfig -e 'print "$Config{sitebin}:$Config{scriptdir}:"' 2>/dev/null):$PATH"
        command -v cpanm
        cpanm --installdeps --notest -v .
        cpanm --test-only -v .
      matrix: >-
        [
          {"platform_name":"omnios","os":"omnios","arch":"x86_64","toolchain":"gcc","perl_version":"5.40.2","configure":"-A'ccflags=-D__EXTENSIONS__ -fno-lto'","prepare":"pkg install -v --accept developer/gcc13 system/header developer/build/make web/curl"},
          {"platform_name":"omnios","os":"omnios","arch":"x86_64","toolchain":"gcc","perl_version":"5.40.2","variant":"dmake","prepare":"pkg install -v --accept developer/gcc13 system/header developer/build/make web/curl"}
        ]

  haiku:
    name: Haiku
    uses: sanko/workflow-testing/.github/workflows/run-vm.yml@main
    with:
      os_version: 'r1beta6'
      checkout_submodules: 'recursive'
      task: |
        export AUTOMATED_TESTING=1 AUTHOR_TESTING=0
        #~ Bootstrap cpanm via a file download, never `curl | perl`: some remote
        #~ sh's run under pipefail, and curl's EPIPE (23) after a clean pipe
        #~ install aborts the whole run even though it succeeded. cpanm lands in
        #~ the active perl's sitebin/scriptdir, which is not on PATH everywhere,
        #~ so re-export those dirs after bootstrapping.
        if command -v curl >/dev/null 2>&1; then curl -fsSL https://cpanmin.us -o /tmp/cpanmin.pl
        elif command -v wget >/dev/null 2>&1; then wget -qO /tmp/cpanmin.pl https://cpanmin.us
        elif command -v fetch >/dev/null 2>&1; then fetch -o /tmp/cpanmin.pl https://cpanmin.us
        else echo 'no http downloader available' >&2; exit 1; fi
        perl /tmp/cpanmin.pl --notest App::cpanminus Module::Build::Tiny
        rm -f /tmp/cpanmin.pl
        export PATH="$(dirname "$(perl -e 'print $^X')"):$(perl -MConfig -e 'print "$Config{sitebin}:$Config{scriptdir}:"' 2>/dev/null):$PATH"
        command -v cpanm
        cpanm --installdeps --notest -v .
        cpanm --test-only -v .
      matrix: >-
        [
          {"platform_name":"haiku","os":"haiku","arch":"x86_64","toolchain":"gcc","prepare":"pkgman install -y cmd:gcc cmd:make cmd:curl cmd:wget cmd:perl"}
        ]

  windows:
    name: Windows
    uses: sanko/workflow-testing/.github/workflows/run-direct.yml@main
    with:
      checkout_submodules: 'recursive'
      task: |
        export AUTOMATED_TESTING=1 AUTHOR_TESTING=1
        if [ -x "/c/cygwin/bin/bash.exe" ]; then
          /c/cygwin/bin/bash.exe --login -eo pipefail -o igncr -c "
            set -e
            cd \"\$(cygpath -u \"$GITHUB_WORKSPACE\")\"
            curl -fsSL https://cpanmin.us -o /tmp/cpanmin.pl
            perl /tmp/cpanmin.pl --notest App::cpanminus Module::Build::Tiny
            rm -f /tmp/cpanmin.pl
            cpanm --installdeps --notest -v .
            cpanm --test-only -v .
          "
        else
          export PATH="/c/Strawberry/perl/site/bin:/c/Strawberry/perl/bin:/c/Strawberry/c/bin:$PATH"
          perl -e 'print qq(perl=$^X :: $^O (make=$Config{make})\n)'
          curl -L https://cpanmin.us | perl - --notest App::cpanminus
          command -v cpanm
          cpanm --installdeps --notest --with-suggests --with-recommends --with-configure -v .
          if [ -n "$AFFIX_USE_DMAKE" ]; then
            perl Build.PL -make=dmake
            ./Build
            ./Build test --v
          else
            cpanm --test-only -v .
          fi
        fi
      matrix: >-
        [
          {"arch":"x86_64","platform_name":"windows","os":"windows-2022","toolchain":"gcc","variant":"5.40.5.1","prepare":"curl -sL -o /c/strawberry.zip https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/SP_54051_64bit/strawberry-perl-5.40.5.1-64bit-portable.zip && rm -rf /c/Strawberry; powershell -NoProfile -Command Expand-Archive -Path C:/strawberry.zip -DestinationPath C:/Strawberry -Force -ErrorAction Stop; rm -f /c/strawberry.zip"},
          {"arch":"x86_64","platform_name":"windows","os":"windows-2022","toolchain":"gcc","variant":"5.42.3.1","prepare":"curl -sL -o /c/strawberry.zip https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/SP_54231_64bit/strawberry-perl-5.42.3.1-64bit-portable.zip && rm -rf /c/Strawberry; powershell -NoProfile -Command Expand-Archive -Path C:/strawberry.zip -DestinationPath C:/Strawberry -Force -ErrorAction Stop; rm -f /c/strawberry.zip"},
          {"arch":"x86_64","platform_name":"windows","os":"windows-2022","toolchain":"gcc","variant":"5.40.5.1-dmake","prepare":"curl -sL -o /c/strawberry.zip https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/SP_54051_64bit/strawberry-perl-5.40.5.1-64bit-portable.zip && rm -rf /c/Strawberry; powershell -NoProfile -Command Expand-Archive -Path C:/strawberry.zip -DestinationPath C:/Strawberry -Force -ErrorAction Stop; rm -f /c/strawberry.zip; curl -sL -o /c/dmake.zip https://cpan.metacpan.org/authors/id/S/SH/SHAY/dmake-4.12.2.2.zip; powershell -NoProfile -Command Expand-Archive -Path C:/dmake.zip -DestinationPath C:/Strawberry/c/bin -Force; rm -f /c/dmake.zip; printf 'AFFIX_USE_DMAKE=1\\n' >> \"$GITHUB_ENV\""},
          {"arch":"x86_64","platform_name":"windows","os":"windows-2022","toolchain":"clang","variant":"5.42.3.1","prepare":"choco install llvm -y; curl -sL -o /c/strawberry.zip https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/SP_54231_64bit/strawberry-perl-5.42.3.1-64bit-portable.zip && rm -rf /c/Strawberry; powershell -NoProfile -Command Expand-Archive -Path C:/strawberry.zip -DestinationPath C:/Strawberry -Force -ErrorAction Stop; rm -f /c/strawberry.zip"},
          {"arch":"aarch64","platform_name":"windows","os":"windows-11-arm","toolchain":"gcc","variant":"5.40.5.1","prepare":"choco install make -y; curl -sL -o /c/strawberry.zip https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/SP_54051_64bit/strawberry-perl-5.40.5.1-64bit-portable.zip && rm -rf /c/Strawberry; powershell -NoProfile -Command Expand-Archive -Path C:/strawberry.zip -DestinationPath C:/Strawberry -Force -ErrorAction Stop; rm -f /c/strawberry.zip"},
          {"arch":"x86_64","platform_name":"windows","os":"windows-2022","toolchain":"msvc","variant":"5.42.3.1","prepare":"curl -sL -o /c/strawberry.zip https://github.com/StrawberryPerl/Perl-Dist-Strawberry/releases/download/SP_54231_64bit/strawberry-perl-5.42.3.1-64bit-portable.zip && rm -rf /c/Strawberry; powershell -NoProfile -Command Expand-Archive -Path C:/strawberry.zip -DestinationPath C:/Strawberry -Force -ErrorAction Stop; rm -f /c/strawberry.zip; set -e; export PATH=\"$(cygpath -u \"$VCToolsInstallDir\")bin/Hostx64/x64:$PATH\"; cl 2>&1 | head -n 1 || true; printf 'AFFIX_CC=cl\\nAFFIX_CXX=cl\\n' >> \"$GITHUB_ENV\""},
          {"arch":"x86_64","platform_name":"cygwin","os":"windows-2022","toolchain":"gcc","variant":"default","prepare":"curl -fsSL -o /c/setup-x86_64.exe https://cygwin.com/setup-x86_64.exe && /c/setup-x86_64.exe --quiet-mode --no-desktop --root C:/cygwin --local-package-dir C:/cygwin/cache --site https://mirrors.kernel.org/sourceware/cygwin/ --packages perl,perl-ExtUtils-CBuilder,gcc-g++,clang,make,curl,libcrypt-devel && rm -f /c/setup-x86_64.exe"}
        ]

  results:
    name: Results
    if: always()
    needs:
      - freebsd
      - linux
      - macos
      - openbsd
      - netbsd
      - dragonflybsd
      - solaris
      - omnios
      - haiku
      - windows
    uses: sanko/workflow-testing/.github/workflows/results-summary.yml@main
    with:
      title: 'Affix.pm CI Matrix'
END
            'workflows/delete_logs.yml' => <<'END',
name: Delete old workflow runs
on:
  workflow_dispatch:
    inputs:
      days:
        description: "Days to retain runs"
        required: true
        default: "30"
      minimum_runs:
        description: "Minimum runs to keep"
        required: true
        default: "6"
      delete_workflow_pattern:
        description: "Workflow name or filename (omit for all). Use `|` to separate multiple filters (e.g. 'build|deploy')."
        required: false
      delete_workflow_by_state_pattern:
        description: "Workflow state: active, deleted, disabled_fork, disabled_inactivity, disabled_manually"
        required: false
        default: "ALL"
        type: choice
        options:
          - "ALL"
          - active
          - deleted
          - disabled_inactivity
          - disabled_manually
      delete_run_by_conclusion_pattern:
        description: "Run conclusion: action_required, cancelled, failure, skipped, success"
        required: false
        default: "ALL"
        type: choice
        options:
          - "ALL"
          - "Unsuccessful: action_required,cancelled,failure,skipped"
          - action_required
          - cancelled
          - failure
          - skipped
          - success
      dry_run:
        description: "Simulate deletions"
        required: false
        default: "false"
        type: choice
        options:
          - "false"
          - "true"
      check_branch_existence:
        description: "Skip deletions linked to an existing branch"
        required: false
        default: "true"
        type: choice
        options:
          - "false"
          - "true"

jobs:
  delete-runs:
    runs-on: ubuntu-latest
    permissions:
      actions: write
      contents: read
    steps:
      - name: Delete workflow runs
        uses: Mattraks/delete-workflow-runs@v2.1.0
        with:
          token: ${{ github.token }}
          repository: ${{ github.repository }}
          retain_days: ${{ github.event.inputs.days }}
          keep_minimum_runs: ${{ github.event.inputs.minimum_runs }}
          delete_workflow_pattern: ${{ github.event.inputs.delete_workflow_pattern }}
          delete_workflow_by_state_pattern: ${{ github.event.inputs.delete_workflow_by_state_pattern }}
          delete_run_by_conclusion_pattern: >-
            ${{
              startsWith(github.event.inputs.delete_run_by_conclusion_pattern, 'Unsuccessful:') &&
              'action_required,cancelled,failure,skipped' ||
              github.event.inputs.delete_run_by_conclusion_pattern
            }}
          check_branch_existence: ${{ github.event.inputs.check_branch_existence }}
          dry_run: ${{ github.event.inputs.dry_run }}
END
        };
    }
}
1;
