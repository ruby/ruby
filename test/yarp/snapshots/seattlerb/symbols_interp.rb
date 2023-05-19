ProgramNode(0...15)(
  ScopeNode(0...0)([]),
  StatementsNode(0...15)(
    [ArrayNode(0...15)(
       [SymbolNode(3...4)(nil, STRING_CONTENT(3...4)("a"), nil, "a"),
        SymbolNode(5...12)(
          nil,
          STRING_CONTENT(5...12)("b\#{1+1}"),
          nil,
          "b\#{1+1}"
        ),
        SymbolNode(13...14)(nil, STRING_CONTENT(13...14)("c"), nil, "c")],
       PERCENT_LOWER_I(0...3)("%i("),
       STRING_END(14...15)(")")
     )]
  )
)
