ProgramNode(0...14)(
  ScopeNode(0...0)([]),
  StatementsNode(0...14)(
    [InterpolatedStringNode(0...9)(
       STRING_BEGIN(0...1)("\""),
       [StringNode(1...4)(nil, STRING_CONTENT(1...4)("a\\n"), nil, "a\n"),
        StringInterpolatedNode(4...8)(
          EMBEXPR_BEGIN(4...6)("\#{"),
          nil,
          EMBEXPR_END(7...8)("}")
        )],
       STRING_END(8...9)("\"")
     ),
     TrueNode(10...14)()]
  )
)
