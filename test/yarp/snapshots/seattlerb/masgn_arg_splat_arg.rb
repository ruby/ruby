ProgramNode(0...12)(
  ScopeNode(0...0)(
    [IDENTIFIER(0...1)("a"), IDENTIFIER(4...5)("b"), IDENTIFIER(7...8)("c")]
  ),
  StatementsNode(0...12)(
    [MultiWriteNode(0...12)(
       [LocalVariableWriteNode(0...1)((0...1), nil, nil, 0),
        SplatNode(3...5)(
          USTAR(3...4)("*"),
          LocalVariableWriteNode(4...5)((4...5), nil, nil, 0)
        ),
        LocalVariableWriteNode(7...8)((7...8), nil, nil, 0)],
       EQUAL(9...10)("="),
       CallNode(11...12)(
         nil,
         nil,
         IDENTIFIER(11...12)("d"),
         nil,
         nil,
         nil,
         nil,
         "d"
       ),
       nil,
       nil
     )]
  )
)
