ProgramNode(0...38)(
  ScopeNode(0...0)([]),
  StatementsNode(0...38)(
    [CaseNode(0...38)(
       ConstantReadNode(5...10)(),
       [InNode(11...24)(
          ConstantReadNode(14...19)(),
          StatementsNode(22...24)(
            [SymbolNode(22...24)(
               SYMBOL_BEGIN(22...23)(":"),
               IDENTIFIER(23...24)("b"),
               nil,
               "b"
             )]
          ),
          (11...13),
          nil
        )],
       ElseNode(25...38)(
         KEYWORD_ELSE(25...29)("else"),
         StatementsNode(32...34)(
           [SymbolNode(32...34)(
              SYMBOL_BEGIN(32...33)(":"),
              IDENTIFIER(33...34)("c"),
              nil,
              "c"
            )]
         ),
         KEYWORD_END(35...38)("end")
       ),
       (0...4),
       (35...38)
     )]
  )
)
