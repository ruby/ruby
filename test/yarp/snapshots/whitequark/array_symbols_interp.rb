ProgramNode(0...29)(
  ScopeNode(0...0)([]),
  StatementsNode(0...29)(
    [ArrayNode(0...14)(
       [SymbolNode(3...6)(nil, STRING_CONTENT(3...6)("foo"), nil, "foo"),
        InterpolatedSymbolNode(0...13)(
          nil,
          [StringInterpolatedNode(7...13)(
             EMBEXPR_BEGIN(7...9)("\#{"),
             StatementsNode(9...12)(
               [CallNode(9...12)(
                  nil,
                  nil,
                  IDENTIFIER(9...12)("bar"),
                  nil,
                  nil,
                  nil,
                  nil,
                  "bar"
                )]
             ),
             EMBEXPR_END(12...13)("}")
           )],
          nil
        )],
       PERCENT_UPPER_I(0...3)("%I["),
       STRING_END(13...14)("]")
     ),
     ArrayNode(16...29)(
       [InterpolatedSymbolNode(0...28)(
          nil,
          [StringNode(19...22)(
             nil,
             STRING_CONTENT(19...22)("foo"),
             nil,
             "foo"
           ),
           StringInterpolatedNode(22...28)(
             EMBEXPR_BEGIN(22...24)("\#{"),
             StatementsNode(24...27)(
               [CallNode(24...27)(
                  nil,
                  nil,
                  IDENTIFIER(24...27)("bar"),
                  nil,
                  nil,
                  nil,
                  nil,
                  "bar"
                )]
             ),
             EMBEXPR_END(27...28)("}")
           )],
          nil
        )],
       PERCENT_UPPER_I(16...19)("%I["),
       STRING_END(28...29)("]")
     )]
  )
)
