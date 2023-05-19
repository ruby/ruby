ProgramNode(0...14)(
  ScopeNode(0...0)([]),
  StatementsNode(0...14)(
    [InterpolatedStringNode(0...14)(
       HEREDOC_START(0...4)("<<-A"),
       [StringNode(5...7)(nil, STRING_CONTENT(5...7)("a\n"), nil, "a\n"),
        StringInterpolatedNode(7...11)(
          EMBEXPR_BEGIN(7...9)("\#{"),
          StatementsNode(9...10)(
            [CallNode(9...10)(
               nil,
               nil,
               IDENTIFIER(9...10)("b"),
               nil,
               nil,
               nil,
               nil,
               "b"
             )]
          ),
          EMBEXPR_END(10...11)("}")
        ),
        StringNode(11...12)(nil, STRING_CONTENT(11...12)("\n"), nil, "\n")],
       HEREDOC_END(12...14)("A\n")
     )]
  )
)
