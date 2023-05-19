ProgramNode(0...21)(
  ScopeNode(0...0)([]),
  StatementsNode(0...21)(
    [CallNode(0...21)(
       nil,
       nil,
       IDENTIFIER(0...1)("p"),
       nil,
       ArgumentsNode(2...21)(
         [InterpolatedStringNode(2...21)(
            HEREDOC_START(2...8)("<<~\"E\""),
            [StringNode(9...19)(
               nil,
               STRING_CONTENT(9...19)("  x\\n   y\n"),
               nil,
               "x\n" + " y\n"
             )],
            HEREDOC_END(19...21)("E\n")
          )]
       ),
       nil,
       nil,
       "p"
     )]
  )
)
