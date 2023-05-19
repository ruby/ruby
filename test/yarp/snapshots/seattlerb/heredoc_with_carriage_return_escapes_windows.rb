ProgramNode(0...29)(
  ScopeNode(0...0)([]),
  StatementsNode(0...29)(
    [InterpolatedStringNode(0...29)(
       HEREDOC_START(0...5)("<<EOS"),
       [StringNode(7...24)(
          nil,
          STRING_CONTENT(7...24)("foo\\rbar\r\n" + "baz\\r\r\n"),
          nil,
          "foo\rbar\r\n" + "baz\r\r\n"
        )],
       HEREDOC_END(24...29)("EOS\r\n")
     )]
  )
)
