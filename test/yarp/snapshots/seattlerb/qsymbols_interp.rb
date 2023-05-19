ProgramNode(0...15)(
  ScopeNode(0...0)([]),
  StatementsNode(0...15)(
    [ArrayNode(0...15)(
       [SymbolNode(3...4)(nil, STRING_CONTENT(3...4)("a"), nil, "a"),
        InterpolatedSymbolNode(0...12)(
          nil,
          [StringNode(5...6)(nil, STRING_CONTENT(5...6)("b"), nil, "b"),
           StringInterpolatedNode(6...12)(
             EMBEXPR_BEGIN(6...8)("\#{"),
             StatementsNode(8...11)(
               [CallNode(8...11)(
                  IntegerNode(8...9)(),
                  nil,
                  PLUS(9...10)("+"),
                  nil,
                  ArgumentsNode(10...11)([IntegerNode(10...11)()]),
                  nil,
                  nil,
                  "+"
                )]
             ),
             EMBEXPR_END(11...12)("}")
           )],
          nil
        ),
        SymbolNode(13...14)(nil, STRING_CONTENT(13...14)("c"), nil, "c")],
       PERCENT_UPPER_I(0...3)("%I("),
       STRING_END(14...15)(")")
     )]
  )
)
