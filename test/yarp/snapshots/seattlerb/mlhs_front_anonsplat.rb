ProgramNode(0...14)(
  ScopeNode(0...0)(
    [IDENTIFIER(3...4)("x"), IDENTIFIER(6...7)("y"), IDENTIFIER(9...10)("z")]
  ),
  StatementsNode(0...14)(
    [MultiWriteNode(0...14)(
       [MultiWriteNode(0...1)(
          [SplatNode(0...1)(USTAR(0...1)("*"), nil)],
          nil,
          nil,
          nil,
          nil
        ),
        LocalVariableWriteNode(3...4)((3...4), nil, nil, 0),
        LocalVariableWriteNode(6...7)((6...7), nil, nil, 0),
        LocalVariableWriteNode(9...10)((9...10), nil, nil, 0)],
       EQUAL(11...12)("="),
       CallNode(13...14)(
         nil,
         nil,
         IDENTIFIER(13...14)("f"),
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
