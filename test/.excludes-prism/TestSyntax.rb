exclude(:test_dedented_heredoc_continued_line, "heredoc line continuation dedent calculation")
exclude(:test_unterminated_heredoc_cr, "quoted \r heredoc terminators should not match \r\n")

exclude(:test_duplicated_when, "https://bugs.ruby-lang.org/issues/20401")
exclude(:test_optional_self_reference, "https://bugs.ruby-lang.org/issues/20478")
exclude(:test_keyword_self_reference, "https://bugs.ruby-lang.org/issues/20478")
