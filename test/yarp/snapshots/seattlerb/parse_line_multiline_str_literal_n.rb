ProgramNode(0...8)(
  ScopeNode(0...0)([]),
  StatementsNode(0...8)(
    [StringNode(0...6)(
       STRING_BEGIN(0...1)("\""),
       STRING_CONTENT(1...5)("a\\nb"),
       STRING_END(5...6)("\""),
       "a\n" + "b"
     ),
     IntegerNode(7...8)()]
  )
)
