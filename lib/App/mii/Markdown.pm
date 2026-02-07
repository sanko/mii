package App::mii::Markdown v0.0.1 {    # based on Pod::Markdown::Github
    use v5.38;
    use parent 'Pod::Markdown';

    sub syntax {
        my ( $self, $paragraph ) = @_;

        #~ https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-and-highlighting-code-blocks
        return 'perl'   if $paragraph =~ /(\b(sub|my|use|shift)\b|\$self|\=\>|\$_|\@_)/;
        return 'cpp'    if $paragraph =~ /#include\s+[<"]/;
        return 'c'      if $paragraph =~ /#include\s+[<"]/;                # Fallback to cpp often works for C but explicit is nice if distinguishable
        return 'python' if $paragraph =~ /\b(def|class|import|from)\b/;
        return 'ruby'   if $paragraph =~ /\b(def|class|module|require)\b/;
        return 'go'     if $paragraph =~ /\b(func|package|import)\b/;
        return 'rust'   if $paragraph =~ /\b(fn|struct|impl|use)\b/;
        return 'js'     if $paragraph =~ /\b(function|const|let|var|import)\b/;
        return 'json'   if $paragraph =~ /^\{/ && $paragraph =~ /: /;
        return 'yaml'   if $paragraph =~ /^---/;
        return 'xml'    if $paragraph =~ /^</;
        return '';
    }

    sub _indent_verbatim {
        my ( $self, $paragraph ) = @_;
        $paragraph = $self->SUPER::_indent_verbatim($paragraph);

        # Remove the leading 4 spaces because we'll escape via ```language
        $paragraph = join "\n", map { s/^\s{4}//; $_ } split /\n/, $paragraph;

        # Enclose the paragraph in ``` and specify the language
        return sprintf( "```%s\n%s\n```", $self->syntax($paragraph), $paragraph );
    }
}
1;
