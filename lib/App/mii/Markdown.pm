package App::mii::Markdown v0.0.1 {    # based on Pod::Markdown::Github
    use v5.38;
    use parent 'Pod::Markdown';

    sub syntax {
        my ( $self, $paragraph ) = @_;

        #~ https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-and-highlighting-code-blocks
        return ( ( $paragraph =~ /(\b(sub|my|use|shift)\b|\$self|\=\>|\$_|\@_)/ ) ? 'perl' : ( $paragraph =~ /#include/ ) ? 'cpp' : '' );

        # TODO: add C, C++, D, Fortran, etc. for Affix
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
