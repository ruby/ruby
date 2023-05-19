ProgramNode(0...15)(
  ScopeNode(0...0)([]),
  StatementsNode(0...15)(
    [InterpolatedSymbolNode(0...15)(
       SYMBOL_BEGIN(0...2)(":\""),
       [StringNode(2...5)(nil, STRING_CONTENT(2...5)("foo"), nil, "foo"),
        StringInterpolatedNode(5...11)(
          EMBEXPR_BEGIN(5...7)("\#{"),
          StatementsNode(7...10)(
            [CallNode(7...10)(
               nil,
               nil,
               IDENTIFIER(7...10)("bar"),
               nil,
               nil,
               nil,
               nil,
               "bar"
             )]
          ),
          EMBEXPR_END(10...11)("}")
        ),
        StringNode(11...14)(nil, STRING_CONTENT(11...14)("baz"), nil, "baz")],
       STRING_END(14...15)("\"")
     )]
  )
)
