ProgramNode(0...35)(
  ScopeNode(0...0)([IDENTIFIER(14...15)("c"), IDENTIFIER(19...23)("rest")]),
  StatementsNode(0...35)(
    [CaseNode(0...35)(
       SymbolNode(5...7)(
         SYMBOL_BEGIN(5...6)(":"),
         IDENTIFIER(6...7)("a"),
         nil,
         "a"
       ),
       [InNode(8...28)(
          HashPatternNode(11...23)(
            nil,
            [AssocNode(11...15)(
               SymbolNode(11...13)(
                 nil,
                 LABEL(11...12)("b"),
                 LABEL_END(12...13)(":"),
                 "b"
               ),
               LocalVariableWriteNode(14...15)((14...15), nil, nil, 0),
               nil
             ),
             AssocSplatNode(17...23)(
               LocalVariableWriteNode(19...23)((19...23), nil, nil, 0),
               (17...19)
             )],
            nil,
            nil,
            nil
          ),
          StatementsNode(29...31)(
            [SymbolNode(29...31)(
               SYMBOL_BEGIN(29...30)(":"),
               IDENTIFIER(30...31)("d"),
               nil,
               "d"
             )]
          ),
          (8...10),
          (24...28)
        )],
       nil,
       (0...4),
       (32...35)
     )]
  )
)
