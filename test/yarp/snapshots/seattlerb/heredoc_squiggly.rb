ProgramNode(0...31)(
  ScopeNode(0...0)([IDENTIFIER(0...1)("a")]),
  StatementsNode(0...31)(
    [LocalVariableWriteNode(0...31)(
       (0...1),
       InterpolatedStringNode(4...31)(
         HEREDOC_START(4...12)("<<~\"EOF\""),
         [StringNode(13...25)(
            nil,
            STRING_CONTENT(13...25)("  x\n" + "  y\n" + "  z\n"),
            nil,
            "x\n" + "y\n" + "z\n"
          )],
         HEREDOC_END(25...31)("  EOF\n")
       ),
       (2...3),
       0
     )]
  )
)
