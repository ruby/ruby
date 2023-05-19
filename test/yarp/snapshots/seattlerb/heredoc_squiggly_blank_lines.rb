ProgramNode(0...24)(
  ScopeNode(0...0)([IDENTIFIER(0...1)("a")]),
  StatementsNode(0...24)(
    [LocalVariableWriteNode(0...24)(
       (0...1),
       InterpolatedStringNode(4...24)(
         HEREDOC_START(4...10)("<<~EOF"),
         [StringNode(11...20)(
            nil,
            STRING_CONTENT(11...20)("  x\n" + "\n" + "  z\n"),
            nil,
            "x\n" + "\n" + "z\n"
          )],
         HEREDOC_END(20...24)("EOF\n")
       ),
       (2...3),
       0
     )]
  )
)
