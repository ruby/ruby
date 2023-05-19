ProgramNode(0...13)(
  ScopeNode(0...0)([IDENTIFIER(2...3)("a"), IDENTIFIER(5...6)("b")]),
  StatementsNode(0...13)(
    [CallNode(0...13)(
       ParenthesesNode(1...13)(
         StatementsNode(2...12)(
           [MultiWriteNode(2...12)(
              [LocalVariableWriteNode(2...3)((2...3), nil, nil, 0),
               LocalVariableWriteNode(5...6)((5...6), nil, nil, 0)],
              EQUAL(7...8)("="),
              CallNode(9...12)(
                nil,
                nil,
                IDENTIFIER(9...12)("foo"),
                nil,
                nil,
                nil,
                nil,
                "foo"
              ),
              nil,
              nil
            )]
         ),
         (1...2),
         (12...13)
       ),
       nil,
       BANG(0...1)("!"),
       nil,
       nil,
       nil,
       nil,
       "!"
     )]
  )
)
