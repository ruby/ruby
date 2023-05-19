ProgramNode(0...12)(
  ScopeNode(0...0)([]),
  StatementsNode(0...12)(
    [InterpolatedStringNode(0...12)(
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
        ),
        StringNode(9...11)(nil, STRING_CONTENT(9...11)(" c"), nil, " c")],
       STRING_END(11...12)("\"")
     )]
  )
)
