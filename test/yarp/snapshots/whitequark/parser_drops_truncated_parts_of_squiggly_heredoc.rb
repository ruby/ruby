ProgramNode(0...19)(
  ScopeNode(0...0)([]),
  StatementsNode(0...19)(
    [InterpolatedStringNode(0...19)(
       HEREDOC_START(0...7)("<<~HERE"),
       [StringNode(8...10)(nil, STRING_CONTENT(8...10)("  "), nil, ""),
        StringInterpolatedNode(10...13)(
          EMBEXPR_BEGIN(10...12)("\#{"),
          nil,
          EMBEXPR_END(12...13)("}")
        ),
        StringNode(13...14)(nil, STRING_CONTENT(13...14)("\n"), nil, "\n")],
       HEREDOC_END(14...19)("HERE\n")
     )]
  )
)
