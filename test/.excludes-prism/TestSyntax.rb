exclude(:test_dedented_heredoc_continued_line, "heredoc line continuation dedent calculation")
exclude(:test_it, "https://github.com/ruby/prism/issues/2323")
exclude(:test_numbered_parameter, "should raise syntax error for numbered parameters in inner blocks")
exclude(:test_unterminated_heredoc_cr, "quoted \r heredoc terminators should not match \r\n")

exclude(:test_duplicated_when, "https://bugs.ruby-lang.org/issues/20401")
exclude(:test_optional_self_reference, "https://bugs.ruby-lang.org/issues/20478")
exclude(:test_keyword_self_reference, "https://bugs.ruby-lang.org/issues/20478")
