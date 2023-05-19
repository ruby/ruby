ProgramNode(0...24)(
  ScopeNode(0...0)([]),
  StatementsNode(0...24)(
    [InterpolatedStringNode(0...24)(
       HEREDOC_START(0...6)("<<~FOO"),
       [StringNode(7...20)(
          nil,
          STRING_CONTENT(7...20)("  baz\\\n" + "  qux\n"),
          nil,
          "baz\n" + "qux\n"
        )],
       HEREDOC_END(20...24)("FOO\n")
     )]
  )
)
