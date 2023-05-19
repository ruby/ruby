ProgramNode(0...27)(
  ScopeNode(0...0)([]),
  StatementsNode(0...27)(
    [InterpolatedStringNode(0...27)(
       HEREDOC_START(0...5)("<<EOS"),
       [StringNode(7...22)(
          nil,
          STRING_CONTENT(7...22)("foo\rbar\r\r\n" + "baz\r\n"),
          nil,
          "foo\rbar\r\r\n" + "baz\r\n"
        )],
       HEREDOC_END(22...27)("EOS\r\n")
     )]
  )
)
