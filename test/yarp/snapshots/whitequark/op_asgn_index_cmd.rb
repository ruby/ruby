ProgramNode(0...18)(
  ScopeNode(0...0)([]),
  StatementsNode(0...18)(
    [OperatorAssignmentNode(0...18)(
       CallNode(0...9)(
         CallNode(0...3)(
           nil,
           nil,
           IDENTIFIER(0...3)("foo"),
           nil,
           nil,
           nil,
           nil,
           "foo"
         ),
         nil,
         BRACKET_LEFT_RIGHT_EQUAL(3...4)("["),
         BRACKET_LEFT(3...4)("["),
         ArgumentsNode(4...8)([IntegerNode(4...5)(), IntegerNode(7...8)()]),
         BRACKET_RIGHT(8...9)("]"),
         nil,
         "[]="
       ),
       PLUS_EQUAL(10...12)("+="),
       CallNode(13...18)(
         nil,
         nil,
         IDENTIFIER(13...14)("m"),
         nil,
         ArgumentsNode(15...18)(
           [CallNode(15...18)(
              nil,
              nil,
              IDENTIFIER(15...18)("foo"),
              nil,
              nil,
              nil,
              nil,
              "foo"
            )]
         ),
         nil,
         nil,
         "m"
       )
     )]
  )
)
