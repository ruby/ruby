ProgramNode(0...17)(
  ScopeNode(0...0)([]),
  StatementsNode(0...17)(
    [InterpolatedStringNode(0...17)(
       HEREDOC_START(0...4)("<<\"\""),
       [StringInterpolatedNode(5...9)(
          EMBEXPR_BEGIN(5...7)("\#{"),
          StatementsNode(7...8)(
            [CallNode(7...8)(
               nil,
               nil,
               IDENTIFIER(7...8)("x"),
               nil,
               nil,
               nil,
               nil,
               "x"
             )]
          ),
          EMBEXPR_END(8...9)("}")
        ),
        StringNode(9...16)(
          nil,
          STRING_CONTENT(9...16)("\n" + "blah2\n"),
          nil,
          "\n" + "blah2\n"
        )],
       HEREDOC_END(16...17)("\n")
     )]
  )
)
