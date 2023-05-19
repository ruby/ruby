ProgramNode(0...16)(
  ScopeNode(0...0)([IDENTIFIER(0...3)("foo"), IDENTIFIER(5...8)("bar")]),
  StatementsNode(0...16)(
    [MultiWriteNode(0...16)(
       [LocalVariableWriteNode(0...3)((0...3), nil, nil, 0),
        LocalVariableWriteNode(5...8)((5...8), nil, nil, 0)],
       EQUAL(9...10)("="),
       CallNode(11...16)(
         nil,
         nil,
         IDENTIFIER(11...12)("m"),
         nil,
         ArgumentsNode(13...16)([LocalVariableReadNode(13...16)(0)]),
         nil,
         nil,
         "m"
       ),
       nil,
       nil
     )]
  )
)
