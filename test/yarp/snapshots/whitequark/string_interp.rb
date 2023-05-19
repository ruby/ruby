ProgramNode(0...14)(
  ScopeNode(0...0)([]),
  StatementsNode(0...14)(
    [InterpolatedStringNode(0...14)(
       STRING_BEGIN(0...1)("\""),
       [StringNode(1...4)(nil, STRING_CONTENT(1...4)("foo"), nil, "foo"),
        StringInterpolatedNode(4...10)(
          EMBEXPR_BEGIN(4...6)("\#{"),
          StatementsNode(6...9)(
            [CallNode(6...9)(
               nil,
               nil,
               IDENTIFIER(6...9)("bar"),
               nil,
               nil,
               nil,
               nil,
               "bar"
             )]
          ),
          EMBEXPR_END(9...10)("}")
        ),
        StringNode(10...13)(nil, STRING_CONTENT(10...13)("baz"), nil, "baz")],
       STRING_END(13...14)("\"")
     )]
  )
)
