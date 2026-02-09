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
jobs:
  etc:
    name: 'FreeBSD/v${{matrix.perl}}'
    needs:
      - setup
    strategy:
      fail-fast: false
      matrix:
        os:
          - architecture: x86-64
            host: ubuntu-latest
            name: freebsd
            pkg: pkg install -y
            version: 14.1
          - architecture: arm64
            host: ubuntu-latest
            name: freebsd
            pkg: pkg install -y
            version: 14.1
        perl:
          - "5.40"
      max-parallel: 5
    uses: ./.github/workflows/cross.yml
    with:
      arch: '${{ matrix.os.architecture }}'
      host: '${{ matrix.os.host }}'
      os: '${{ matrix.os.name }}'
      perl: '${{ matrix.perl }}'
      pkg: '${{ matrix.os.pkg }}'
      version: '${{ matrix.os.version }}'
      setup: '${{ matrix.os.setup }}'
  linux:
    name: 'Linux/v${{matrix.perl}}'
    needs:
      - setup
    strategy:
      fail-fast: false
      matrix:
        flags:
          - ''
          - -Dusethreads
          - -Duselongdouble
          - -Dusequadmath
        os:
          - ubuntu-24.04
        perl: '${{ fromJSON(needs.setup.outputs.matrix).perl }}'
      max-parallel: 25
    uses: ./.github/workflows/unix.yml
    with:
      flags: '${{ matrix.flags }}'
      os: '${{ matrix.os }}'
      perl: '${{ matrix.perl }}'
  macos:
    name: "[${{ matrix.os == 'macos-15-intel' && 'Intel' || 'M1' }}] macOS/v${{matrix.perl}}"
    needs:
      - setup
    strategy:
      fail-fast: false
      matrix:
        exclude:
          - flags: -Dusequadmath
          - flags: -Dusethreads
        flags: '${{ fromJSON(needs.setup.outputs.matrix).flags }}'
        os:
          - macos-15-intel
          - macos-15
        perl: '${{ fromJSON(needs.setup.outputs.matrix).perl }}'
      max-parallel: 25
    uses: ./.github/workflows/unix.yml
    with:
      flags: '${{ matrix.flags }}'
      os: '${{ matrix.os }}'
      perl: '${{ matrix.perl }}'
  results:
    name: Results
    needs:
      - macos
      - win32
      - linux
    runs-on: ubuntu-22.04
    steps:
      - name: Download test results
        uses: actions/download-artifact@v4
        with:
          path: artifacts
      - name: Report test results
        run: |
          # Function to process a directory
          process_dir() {
            local dir="$1"
            # Loop through each element in the directory
            for file in "$dir"/*; do
              # Check if it's a directory
              if [ -d "$file" ]; then
                # Recursively call process_dir for subdirectories (except .)
                if [ "$file" != "." ]; then
                  process_dir "$file"
                fi
              # If it's a regular file, print its content
              elif [ -f "$file" ]; then
                echo "================> $file <================"
                cat "$file"
                echo ""  # Add an empty line between files
              fi
            done
          }
          # Get the directory path from the first argument (or current directory)
          dir=${1:-.}
          # Process the specified directory
          process_dir "artifacts"
  setup:
    name: Generate Testing Matrix
    outputs:
      matrix: '${{ steps.matrix.outputs.matrix }}'
    runs-on: ubuntu-22.04
    steps:
      - env:
          DATA: |
            {
              "perl":  ["5.42.0"],
              "flags": ["", "-Dusethreads", "-Duselongdouble", "-Dusequadmath"]
            }
        id: matrix
        run: |
          jq -rn 'env.DATA | fromjson | @json "matrix=\(.)"' > $GITHUB_OUTPUT
  win32:
    name: 'Windows/v${{matrix.perl}}'
    needs:
      - setup
    strategy:
      fail-fast: false
      matrix:
        exclude:
          - flags: -Duselongdouble
          - flags: -Dusequadmath
        flags:
          - -Dusethreads
          - ''
        os:
          - windows-2022
        perl: '${{ fromJSON(needs.setup.outputs.matrix).perl }}'
      max-parallel: 25
    uses: ./.github/workflows/win32.yml
    with:
      flags: '${{ matrix.flags }}'
      os: '${{ matrix.os }}'
      perl: '${{ matrix.perl }}'

name: CI Matrix

on:
  pull_request: ~
  push: ~
  schedule:
    - cron: 42 5 * * 0
  workflow_dispatch: ~

permissions:
  contents: read
  # actions: read is required to list artifacts via the API
  actions: read
END
            'workflows/cross.yml' => <<'END',
---
jobs:
  build:
    name: "[${{ inputs.arch }}] ${{ inputs.os == 'freebsd' && 'FreeBSD' ||  inputs.os == 'openbsd' && 'OpenBSD' || inputs.os }} ${{ inputs.version }}"
    runs-on: '${{ inputs.host }}'
    steps:
      - uses: actions/checkout@v5.0.0
        with:
          submodules: true
      - env:
          AUTHOR_TESTING: 0
          AUTOMATED_TESTING: 1
        name: 'Test on ${{ inputs.os }}'
        uses: cross-platform-actions/action@v0.32.0
        with:
          architecture: '${{ inputs.arch }}'
          cpu_count: 4
          environment_variables: AUTHOR_TESTING AUTOMATED_TESTING
          memory: 5G
          operating_system: '${{ inputs.os }}'
          run: |
            uname -a
            echo $SHELL
            pwd
            ls -lah
            whoami
            env | sort
            ${{ inputs.setup }}
            sudo ${{inputs.pkg}} perl5
            perl -v
            curl -L https://cpanmin.us | sudo perl - --notest App::cpanminus Module::Build::Tiny
            sudo cpanm --installdeps --notest .
            sudo cpanm --test-only -v .
            command1_exit_code=$?
            # Check if the first command exited successfully (exit code 0)
            if [ $command1_exit_code -eq 0 ]; then
              # Run the second command
              sudo perl -V > test-output-${{ inputs.os }}-${{ inputs.version }}-perl${{ inputs.perl }}.${{inputs.perl_subversion}}-${{ inputs.arch }}.txt
              command2_exit_code=$?
            else
              # Print error message to a file (replace "error.log" with your desired filename)
              echo "Error!" > test-output-${{ inputs.os }}-${{ inputs.version }}-perl${{ inputs.perl }}.${{inputs.perl_subversion}}-${{ inputs.arch }}.txt
              # Exit with the first command's exit code
              exit $command1_exit_code
            fi
          shell: bash
          version: '${{ inputs.version }}'
      - name: Upload results as artifact
        uses: actions/upload-artifact@v5.0.0
        continue-on-error: true
        with:
          if-no-files-found: error
          name: 'test-output-${{ inputs.os }}-${{ inputs.version }}-perl${{ inputs.perl }}.${{inputs.perl_subversion}}-${{ inputs.arch }}'
          path: 'test-output-${{ inputs.os }}-${{ inputs.version }}-perl${{ inputs.perl }}.${{inputs.perl_subversion}}-${{ inputs.arch }}.txt'
name: bsd module
on:
  workflow_call:
    inputs:
      arch:
        required: true
        type: string
      host:
        required: true
        type: string
      os:
        required: true
        type: string
      perl:
        required: true
        type: string
      perl_subversion:
        required: false
        type: string
        default: "2"
      pkg:
        required: true
        type: string
      version:
        required: true
        type: string
      setup:
        required: false
        type: string
        default: ""
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
            'workflows/unix.yml' => <<'END',
---
jobs:
  build:
    name: "${{ inputs.flags == '-Dusethreads' && 'Threads' ||inputs.flags == '-Duselongdouble' && 'Long Double' || inputs.flags == '-Dusequadmath' && 'Quad Math' || 'Default' }}"
    runs-on: '${{ inputs.os }}'
    steps:
      - name: Checkout source
        uses: actions/checkout@v5.0.0
        with:
          submodules: true
      - id: cache-perl
        name: Check perl Cache
        uses: actions/cache@v4.3.0
        with:
          key: '${{ inputs.os }}-perl-v${{ inputs.perl }}${{ inputs.flags }}'
          path: '~/perl5/'
      - if: "${{ steps.cache-perl.outputs.cache-hit != 'true' }}"
        name: 'Build perl ${{ inputs.perl }} from source'
        run: |
          \curl -L https://install.perlbrew.pl | bash
          source ~/perl5/perlbrew/etc/bashrc

          perlbrew self-upgrade
          perlbrew install-patchperl
          perlbrew available
          perlbrew install-cpanm
          cpanm --local-lib=~/perl5 local::lib && eval $(perl -I ~/perl5/lib/perl5/ -Mlocal::lib)
          cpanm -n -v Devel::PatchPerl

          perlbrew install --switch --verbose --as cache-${{ inputs.os }}-${{ inputs.perl }}${{ inputs.flags }} -j 12 --notest --noman ${{ inputs.flags }} perl-${{ inputs.perl }}
      - name: Install prereqs
        run: |
          if [[ $(uname -o) == GNU/Linux ]]; then
            sudo apt-get update -y
            sudo apt-get install -y valgrind
          fi
          source ~/perl5/perlbrew/etc/bashrc
          perlbrew switch cache-${{ inputs.os }}-${{ inputs.perl }}${{ inputs.flags }}
          cpanm --installdeps --notest --with-suggests --with-recommends --with-configure -v .
        shell: bash
      - env:
          AUTHOR_TESTING: 0
          AUTOMATED_TESTING: 1
        id: test
        name: Run test suite
        run: |
          source ~/perl5/perlbrew/etc/bashrc
          perlbrew switch cache-${{ inputs.os }}-${{ inputs.perl }}${{ inputs.flags }}
          perl Build.PL
          ./Build
          ./Build test --v
          command1_exit_code=$?
          if [ $command1_exit_code -eq 0 ]; then
            ~/perl5/perlbrew/perls/cache-${{ inputs.os }}-${{ inputs.perl }}${{ inputs.flags }}/bin/perl -V > test-output-${{ inputs.os }}-${{ inputs.perl }}${{ inputs.flags }}.txt
            command2_exit_code=$?
          else
            echo "Error!" > test-output-${{ inputs.os }}-${{ inputs.perl }}${{ inputs.flags }}.txt
            exit $command1_exit_code
          fi
        shell: bash
      - name: Upload results as artifact
        uses: actions/upload-artifact@v5.0.0
        with:
          if-no-files-found: error
          name: 'test-output-${{ inputs.os }}-${{ inputs.perl }}${{ inputs.flags }}'
          path: 'test-output-${{ inputs.os }}-${{ inputs.perl }}${{ inputs.flags }}.txt'
          retention-days: 1
name: inputs module
on:
  workflow_call:
    inputs:
      flags:
        required: false
        type: string
      os:
        required: true
        type: string
      perl:
        required: true
        type: string
END
            'workflows/win32.yml' => <<'END',
---
jobs:
  build:
    name: "${{ inputs.flags == '-Dusethreads' && 'Strawberry' || 'Default' }}"
    runs-on: '${{ inputs.os }}'
    steps:
      - uses: actions/checkout@v5.0.0
        with:
          submodules: true
      - name: Setup Perl environment
        uses: shogo82148/actions-setup-perl@v1.37.0
        with:
          distribution: "${{ inputs.flags == '-Dusethreads' && 'strawberry' || 'default' }}"
          install-modules-args: --with-configure --installdeps --notest -v .
          install-modules-with: cpanm
          multi-thread: "${{ inputs.flags == '-Dusethreads' && true || false }}"
          perl-version: '${{ inputs.perl }}'
      - name: Install prereqs
        run: cpanm --installdeps --notest -v .
      - name: Run tests
        run: |
          perl -V

          perl Build.PL
          ./Build
          ./Build test --v

          if ($LASTEXITCODE -eq 0) {
            perl -V > test-output-${{ inputs.os }}-${{ inputs.perl }}${{ inputs.flags }}.txt
          } else {
            Out-File -FilePath "test-output-${{ inputs.os }}-${{ inputs.perl }}${{ inputs.flags }}.txt" -InputObject "Error" -Append
            exit $LASTEXITCODE
          }
      - name: Upload results as artifact
        uses: actions/upload-artifact@v5.0.0
        with:
          if-no-files-found: error
          name: 'test-output-${{ inputs.os }}-${{ inputs.perl }}${{ inputs.flags }}'
          path: 'test-output-${{ inputs.os }}-${{ inputs.perl }}${{ inputs.flags }}.txt'
          retention-days: 1
name: windows module
on:
  workflow_call:
    inputs:
      flags:
        required: false
        type: string
      os:
        required: true
        type: string
      perl:
        required: true
        type: string
END
        };
    }
}
1;
