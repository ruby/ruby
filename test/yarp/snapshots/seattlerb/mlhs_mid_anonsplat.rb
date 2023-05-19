ProgramNode(0...23)(
  ScopeNode(0...0)(
    [IDENTIFIER(0...1)("a"),
     IDENTIFIER(3...4)("b"),
     IDENTIFIER(6...7)("c"),
     IDENTIFIER(12...13)("x"),
     IDENTIFIER(15...16)("y"),
     IDENTIFIER(18...19)("z")]
  ),
  StatementsNode(0...23)(
    [MultiWriteNode(0...23)(
       [LocalVariableWriteNode(0...1)((0...1), nil, nil, 0),
        LocalVariableWriteNode(3...4)((3...4), nil, nil, 0),
        LocalVariableWriteNode(6...7)((6...7), nil, nil, 0),
        SplatNode(9...10)(USTAR(9...10)("*"), nil),
        LocalVariableWriteNode(12...13)((12...13), nil, nil, 0),
        LocalVariableWriteNode(15...16)((15...16), nil, nil, 0),
        LocalVariableWriteNode(18...19)((18...19), nil, nil, 0)],
       EQUAL(20...21)("="),
       CallNode(22...23)(
         nil,
         nil,
         IDENTIFIER(22...23)("f"),
         nil,
         nil,
         nil,
         nil,
         "f"
       ),
       nil,
       nil
     )]
  )
)
