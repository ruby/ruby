ProgramNode(0...8)(
  ScopeNode(0...0)([IDENTIFIER(3...4)("a")]),
  StatementsNode(0...8)(
    [MultiWriteNode(0...8)(
       [MultiWriteNode(0...1)(
          [SplatNode(0...1)(USTAR(0...1)("*"), nil)],
          nil,
          nil,
          nil,
          nil
        ),
        LocalVariableWriteNode(3...4)((3...4), nil, nil, 0)],
       EQUAL(5...6)("="),
       CallNode(7...8)(
         nil,
         nil,
         IDENTIFIER(7...8)("b"),
         nil,
         nil,
         nil,
         nil,
         "b"
       ),
       nil,
       nil
     )]
  )
)
