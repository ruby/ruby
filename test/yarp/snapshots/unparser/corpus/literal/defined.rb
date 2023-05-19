ProgramNode(0...56)(
  ScopeNode(0...0)([IDENTIFIER(40...41)("a"), IDENTIFIER(43...44)("b")]),
  StatementsNode(0...56)(
    [DefinedNode(0...14)(
       PARENTHESIS_LEFT(8...9)("("),
       InstanceVariableReadNode(9...13)(),
       PARENTHESIS_RIGHT(13...14)(")"),
       (0...8)
     ),
     DefinedNode(15...28)(
       PARENTHESIS_LEFT(23...24)("("),
       ConstantReadNode(24...27)(),
       PARENTHESIS_RIGHT(27...28)(")"),
       (15...23)
     ),
     DefinedNode(29...56)(
       PARENTHESIS_LEFT(37...38)("("),
       ParenthesesNode(38...55)(
         StatementsNode(40...54)(
           [MultiWriteNode(40...54)(
              [LocalVariableWriteNode(40...41)((40...41), nil, nil, 0),
               LocalVariableWriteNode(43...44)((43...44), nil, nil, 0)],
              EQUAL(46...47)("="),
              ArrayNode(48...54)(
                [IntegerNode(49...50)(), IntegerNode(52...53)()],
                BRACKET_LEFT_ARRAY(48...49)("["),
                BRACKET_RIGHT(53...54)("]")
              ),
              (39...40),
              (44...45)
            )]
         ),
         (38...39),
         (54...55)
       ),
       PARENTHESIS_RIGHT(55...56)(")"),
       (29...37)
     )]
  )
)
