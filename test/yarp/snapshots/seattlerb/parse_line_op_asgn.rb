ProgramNode(6...34)(
  ScopeNode(0...0)([IDENTIFIER(6...9)("foo")]),
  StatementsNode(6...34)(
    [OperatorAssignmentNode(6...24)(
       LocalVariableWriteNode(6...9)((6...9), nil, nil, 0),
       PLUS_EQUAL(10...12)("+="),
       CallNode(21...24)(
         nil,
         nil,
         IDENTIFIER(21...24)("bar"),
         nil,
         nil,
         nil,
         nil,
         "bar"
       )
     ),
     CallNode(31...34)(
       nil,
       nil,
       IDENTIFIER(31...34)("baz"),
       nil,
       nil,
       nil,
       nil,
       "baz"
     )]
  )
)
