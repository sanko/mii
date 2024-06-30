requires 'perl', '5.038';    # Built on new class syntax
requires 'JSON::Tiny';
requires 'Template::Tiny';
requires 'Getopt::Long';
requires 'Pod::Usage';
requires 'Software::License';
requires 'Carp';
requires 'Path::Tiny';
requires 'Module::Build::Tiny';
requires 'CPAN::Meta::Prereqs';
requires 'CPAN::Meta';
requires 'Module::CPANfile';
requires 'Module::Metadata';
requires 'Pod::Markdown';
on 'test' => sub {
    requires 'Test2::V0';
    requires 'Capture::Tiny';
};
on 'configure' => sub {
    requires 'Archive::Tar';
    requires 'CPAN::Meta';
    requires 'Module::Build::Tiny';
    requires 'HTTP::Tiny';
    requires 'File::Spec::Functions';
    requires 'File::Basename';
    requires 'File::Which';
    requires 'File::Temp';
    requires 'Path::Tiny';
};
