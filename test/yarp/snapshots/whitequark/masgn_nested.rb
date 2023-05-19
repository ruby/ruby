ProgramNode(2...30)(
  ScopeNode(0...0)(
    [IDENTIFIER(2...3)("b"),
     IDENTIFIER(15...16)("a"),
     IDENTIFIER(22...23)("c")]
  ),
  StatementsNode(2...30)(
    [MultiWriteNode(2...13)(
       [MultiWriteNode(2...4)(
          [LocalVariableWriteNode(2...3)((2...3), nil, nil, 0),
           SplatNode(3...4)(COMMA(3...4)(","), nil)],
          nil,
          nil,
          (1...2),
          (5...6)
        )],
       EQUAL(8...9)("="),
       CallNode(10...13)(
         nil,
         nil,
         IDENTIFIER(10...13)("foo"),
         nil,
         nil,
         nil,
         nil,
         "foo"
       ),
       (0...1),
       (6...7)
     ),
     MultiWriteNode(15...30)(
       [LocalVariableWriteNode(15...16)((15...16), nil, nil, 0),
        MultiWriteNode(19...24)(
          [LocalVariableWriteNode(19...20)((19...20), nil, nil, 0),
           LocalVariableWriteNode(22...23)((22...23), nil, nil, 0)],
          nil,
          nil,
          (18...19),
          (23...24)
        )],
       EQUAL(25...26)("="),
       CallNode(27...30)(
         nil,
         nil,
         IDENTIFIER(27...30)("foo"),
         nil,
         nil,
         nil,
         nil,
         "foo"
       ),
       nil,
       nil
     )]
  )
)
