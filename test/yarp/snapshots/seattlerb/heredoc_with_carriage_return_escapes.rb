ProgramNode(0...25)(
  ScopeNode(0...0)([]),
  StatementsNode(0...25)(
    [InterpolatedStringNode(0...25)(
       HEREDOC_START(0...5)("<<EOS"),
       [StringNode(6...21)(
          nil,
          STRING_CONTENT(6...21)("foo\\rbar\n" + "baz\\r\n"),
          nil,
          "foo\rbar\n" + "baz\r\n"
        )],
       HEREDOC_END(21...25)("EOS\n")
     )]
  )
)
