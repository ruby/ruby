ProgramNode(0...48)(
  ScopeNode(0...0)([IDENTIFIER(24...25)("b"), IDENTIFIER(38...39)("c")]),
  StatementsNode(0...48)(
    [IfNode(0...46)(
       KEYWORD_IF(0...2)("if"),
       TrueNode(3...7)(),
       StatementsNode(15...42)(
         [CallNode(15...21)(
            nil,
            nil,
            IDENTIFIER(15...16)("p"),
            PARENTHESIS_LEFT(16...17)("("),
            ArgumentsNode(17...20)(
              [StringNode(17...20)(
                 STRING_BEGIN(17...18)("'"),
                 STRING_CONTENT(18...19)("a"),
                 STRING_END(19...20)("'"),
                 "a"
               )]
            ),
            PARENTHESIS_RIGHT(20...21)(")"),
            nil,
            "p"
          ),
          LocalVariableWriteNode(24...29)(
            (24...25),
            IntegerNode(28...29)(),
            (26...27),
            0
          ),
          CallNode(32...35)(
            nil,
            nil,
            IDENTIFIER(32...33)("p"),
            nil,
            ArgumentsNode(34...35)([LocalVariableReadNode(34...35)(0)]),
            nil,
            nil,
            "p"
          ),
          LocalVariableWriteNode(38...42)(
            (38...39),
            IntegerNode(41...42)(),
            (40...41),
            0
          )]
       ),
       nil,
       KEYWORD_END(43...46)("end")
     ),
     CallNode(47...48)(
       nil,
       nil,
       IDENTIFIER(47...48)("a"),
       nil,
       nil,
       nil,
       nil,
       "a"
     )]
  )
)
