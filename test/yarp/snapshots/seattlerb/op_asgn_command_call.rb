ProgramNode(0...11)(
  ScopeNode(0...0)([IDENTIFIER(0...1)("a")]),
  StatementsNode(0...11)(
    [OperatorOrAssignmentNode(0...11)(
       LocalVariableWriteNode(0...1)((0...1), nil, nil, 0),
       CallNode(6...11)(
         CallNode(6...7)(
           nil,
           nil,
           IDENTIFIER(6...7)("b"),
           nil,
           nil,
           nil,
           nil,
           "b"
         ),
         DOT(7...8)("."),
         IDENTIFIER(8...9)("c"),
         nil,
         ArgumentsNode(10...11)([IntegerNode(10...11)()]),
         nil,
         nil,
         "c"
       ),
       (2...5)
     )]
  )
)
