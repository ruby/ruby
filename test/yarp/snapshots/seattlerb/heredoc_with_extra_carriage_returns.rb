ProgramNode(0...23)(
  ScopeNode(0...0)([]),
  StatementsNode(0...23)(
    [InterpolatedStringNode(0...23)(
       HEREDOC_START(0...5)("<<EOS"),
       [StringNode(6...19)(
          nil,
          STRING_CONTENT(6...19)("foo\rbar\r\n" + "baz\n"),
          nil,
          "foo\rbar\r\n" + "baz\n"
        )],
       HEREDOC_END(19...23)("EOS\n")
     )]
  )
)
