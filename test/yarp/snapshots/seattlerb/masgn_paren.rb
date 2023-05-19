ProgramNode(1...12)(
  ScopeNode(0...0)([IDENTIFIER(1...2)("a"), IDENTIFIER(4...5)("b")]),
  StatementsNode(1...12)(
    [MultiWriteNode(1...12)(
       [LocalVariableWriteNode(1...2)((1...2), nil, nil, 0),
        LocalVariableWriteNode(4...5)((4...5), nil, nil, 0)],
       EQUAL(7...8)("="),
       CallNode(9...12)(
         CallNode(9...10)(
           nil,
           nil,
           IDENTIFIER(9...10)("c"),
           nil,
           nil,
           nil,
           nil,
           "c"
         ),
         DOT(10...11)("."),
         IDENTIFIER(11...12)("d"),
         nil,
         nil,
         nil,
         nil,
         "d"
       ),
       (0...1),
       (5...6)
     )]
  )
)
