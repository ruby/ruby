ProgramNode(0...46)(
  ScopeNode(0...0)([]),
  StatementsNode(0...46)(
    [CallNode(0...19)(
       nil,
       nil,
       IDENTIFIER(0...3)("fun"),
       PARENTHESIS_LEFT(3...4)("("),
       ArgumentsNode(4...18)(
         [CallNode(4...7)(
            nil,
            nil,
            IDENTIFIER(4...7)("foo"),
            nil,
            nil,
            nil,
            nil,
            "foo"
          ),
          HashNode(9...18)(
            nil,
            [AssocNode(9...18)(
               SymbolNode(9...13)(
                 SYMBOL_BEGIN(9...10)(":"),
                 IDENTIFIER(10...13)("foo"),
                 nil,
                 "foo"
               ),
               IntegerNode(17...18)(),
               EQUAL_GREATER(14...16)("=>")
             )],
            nil
          )]
       ),
       PARENTHESIS_RIGHT(18...19)(")"),
       nil,
       "fun"
     ),
     CallNode(21...46)(
       nil,
       nil,
       IDENTIFIER(21...24)("fun"),
       PARENTHESIS_LEFT(24...25)("("),
       ArgumentsNode(25...45)(
         [CallNode(25...28)(
            nil,
            nil,
            IDENTIFIER(25...28)("foo"),
            nil,
            nil,
            nil,
            nil,
            "foo"
          ),
          HashNode(30...39)(
            nil,
            [AssocNode(30...39)(
               SymbolNode(30...34)(
                 SYMBOL_BEGIN(30...31)(":"),
                 IDENTIFIER(31...34)("foo"),
                 nil,
                 "foo"
               ),
               IntegerNode(38...39)(),
               EQUAL_GREATER(35...37)("=>")
             )],
            nil
          ),
          BlockArgumentNode(41...45)(
            CallNode(42...45)(
              nil,
              nil,
              IDENTIFIER(42...45)("baz"),
              nil,
              nil,
              nil,
              nil,
              "baz"
            ),
            (41...42)
          )]
       ),
       PARENTHESIS_RIGHT(45...46)(")"),
       nil,
       "fun"
     )]
  )
)
