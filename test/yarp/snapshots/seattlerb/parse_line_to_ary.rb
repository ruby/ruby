ProgramNode(0...10)(
  ScopeNode(0...0)([IDENTIFIER(0...1)("a"), IDENTIFIER(3...4)("b")]),
  StatementsNode(0...10)(
    [MultiWriteNode(0...8)(
       [LocalVariableWriteNode(0...1)((0...1), nil, nil, 0),
        LocalVariableWriteNode(3...4)((3...4), nil, nil, 0)],
       EQUAL(5...6)("="),
       CallNode(7...8)(
         nil,
         nil,
         IDENTIFIER(7...8)("c"),
         nil,
         nil,
         nil,
         nil,
         "c"
       ),
       nil,
       nil
     ),
     CallNode(9...10)(
       nil,
       nil,
       IDENTIFIER(9...10)("d"),
       nil,
       nil,
       nil,
       nil,
       "d"
     )]
  )
)
