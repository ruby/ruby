ProgramNode(0...25)(
  ScopeNode(0...0)([IDENTIFIER(0...1)("a")]),
  StatementsNode(0...25)(
    [LocalVariableWriteNode(0...25)(
       (0...1),
       InterpolatedStringNode(4...25)(
         HEREDOC_START(4...10)("<<~EOF"),
         [StringNode(11...21)(
            nil,
            STRING_CONTENT(11...21)("  x\n" + " \n" + "  z\n"),
            nil,
            "x\n" + "\n" + "z\n"
          )],
         HEREDOC_END(21...25)("EOF\n")
       ),
       (2...3),
       0
     )]
  )
)
