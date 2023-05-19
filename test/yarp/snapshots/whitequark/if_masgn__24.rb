ProgramNode(0...20)(
  ScopeNode(0...0)([IDENTIFIER(4...5)("a"), IDENTIFIER(7...8)("b")]),
  StatementsNode(0...20)(
    [IfNode(0...20)(
       KEYWORD_IF(0...2)("if"),
       ParenthesesNode(3...15)(
         StatementsNode(4...14)(
           [MultiWriteNode(4...14)(
              [LocalVariableWriteNode(4...5)((4...5), nil, nil, 0),
               LocalVariableWriteNode(7...8)((7...8), nil, nil, 0)],
              EQUAL(9...10)("="),
              CallNode(11...14)(
                nil,
                nil,
                IDENTIFIER(11...14)("foo"),
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
         (3...4),
         (14...15)
       ),
       nil,
       nil,
       KEYWORD_END(17...20)("end")
     )]
  )
)
