ProgramNode(0...24)(
  ScopeNode(0...0)([]),
  StatementsNode(0...24)(
    [CallNode(0...24)(
       nil,
       nil,
       IDENTIFIER(0...1)("a"),
       PARENTHESIS_LEFT(1...2)("("),
       ArgumentsNode(2...12)(
         [HashNode(2...12)(
            nil,
            [AssocNode(2...12)(
               SymbolNode(2...4)(
                 nil,
                 LABEL(2...3)("b"),
                 LABEL_END(3...4)(":"),
                 "b"
               ),
               IfNode(5...12)(
                 KEYWORD_IF(5...7)("if"),
                 SymbolNode(8...10)(
                   SYMBOL_BEGIN(8...9)(":"),
                   IDENTIFIER(9...10)("c"),
                   nil,
                   "c"
                 ),
                 StatementsNode(11...12)([IntegerNode(11...12)()]),
                 ElseNode(13...23)(
                   KEYWORD_ELSE(13...17)("else"),
                   StatementsNode(18...19)([IntegerNode(18...19)()]),
                   KEYWORD_END(20...23)("end")
                 ),
                 KEYWORD_END(20...23)("end")
               ),
               nil
             )],
            nil
          )]
       ),
       PARENTHESIS_RIGHT(23...24)(")"),
       nil,
       "a"
     )]
  )
)
