ProgramNode(0...12)(
  ScopeNode(0...0)([IDENTIFIER(1...2)("a")]),
  StatementsNode(0...12)(
    [MultiWriteNode(0...12)(
       [SplatNode(0...2)(
          USTAR(0...1)("*"),
          LocalVariableWriteNode(1...2)((1...2), nil, nil, 0)
        )],
       EQUAL(3...4)("="),
       ArrayNode(0...12)(
         [IntegerNode(5...6)(), IntegerNode(8...9)(), IntegerNode(11...12)()],
         nil,
         nil
       ),
       nil,
       nil
     )]
  )
)
