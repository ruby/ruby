ProgramNode(0...10)(
  ScopeNode(0...0)([]),
  StatementsNode(0...10)(
    [InterpolatedStringNode(0...10)(
       STRING_BEGIN(0...1)("\""),
       [StringNode(1...3)(nil, STRING_CONTENT(1...3)("a "), nil, "a "),
        StringInterpolatedNode(3...9)(
          EMBEXPR_BEGIN(3...5)("\#{"),
          StatementsNode(5...8)(
            [StringNode(5...8)(
               STRING_BEGIN(5...6)("'"),
               STRING_CONTENT(6...7)("b"),
               STRING_END(7...8)("'"),
               "b"
             )]
          ),
          EMBEXPR_END(8...9)("}")
        )],
       STRING_END(9...10)("\"")
     )]
  )
)
