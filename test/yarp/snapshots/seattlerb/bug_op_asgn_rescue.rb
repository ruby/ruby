ProgramNode(0...18)(
  ScopeNode(0...0)([IDENTIFIER(0...1)("a")]),
  StatementsNode(0...18)(
    [OperatorOrAssignmentNode(0...18)(
       LocalVariableWriteNode(0...1)((0...1), nil, nil, 0),
       RescueModifierNode(6...18)(
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
         KEYWORD_RESCUE_MODIFIER(8...14)("rescue"),
         NilNode(15...18)()
       ),
       (2...5)
     )]
  )
)
