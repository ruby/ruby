ProgramNode(0...43)(
  ScopeNode(0...0)([IDENTIFIER(0...1)("a")]),
  StatementsNode(0...43)(
    [LocalVariableWriteNode(0...43)(
       (0...1),
       InterpolatedStringNode(4...43)(
         HEREDOC_START(4...12)("<<~\"EOF\""),
         [StringNode(13...37)(
            nil,
            STRING_CONTENT(13...37)("  blah blah\n" + " \tblah blah\n"),
            nil,
            "blah blah\n" + "\tblah blah\n"
          )],
         HEREDOC_END(37...43)("  EOF\n")
       ),
       (2...3),
       0
     )]
  )
)
