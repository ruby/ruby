ProgramNode(0...27)(
  ScopeNode(0...0)([IDENTIFIER(0...1)("s")]),
  StatementsNode(0...27)(
    [LocalVariableWriteNode(0...27)(
       (0...1),
       InterpolatedStringNode(4...27)(
         HEREDOC_START(4...10)("<<-EOS"),
         [StringNode(11...23)(
            nil,
            STRING_CONTENT(11...23)("a\\247b\n" + "cöd\n"),
            nil,
            "a\xA7b\n" + "cöd\n"
          )],
         HEREDOC_END(23...27)("EOS\n")
       ),
       (2...3),
       0
     )]
  )
)
