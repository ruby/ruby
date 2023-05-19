ProgramNode(0...12)(
  ScopeNode(0...0)(
    [IDENTIFIER(1...2)("a"), IDENTIFIER(4...5)("b"), IDENTIFIER(7...8)("c")]
  ),
  StatementsNode(0...12)(
    [MultiWriteNode(0...12)(
       [MultiWriteNode(0...2)(
          [SplatNode(0...2)(
             USTAR(0...1)("*"),
             LocalVariableWriteNode(1...2)((1...2), nil, nil, 0)
           )],
          nil,
          nil,
          nil,
          nil
        ),
        LocalVariableWriteNode(4...5)((4...5), nil, nil, 0),
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
