ProgramNode(0...28)(
  ScopeNode(0...0)([IDENTIFIER(19...20)("c")]),
  StatementsNode(0...28)(
    [CaseNode(0...28)(
       SymbolNode(5...7)(
         SYMBOL_BEGIN(5...6)(":"),
         IDENTIFIER(6...7)("a"),
         nil,
         "a"
       ),
       [InNode(8...24)(
          FindPatternNode(11...24)(
            nil,
            SplatNode(12...13)(USTAR(12...13)("*"), nil),
            [SymbolNode(15...17)(
               SYMBOL_BEGIN(15...16)(":"),
               IDENTIFIER(16...17)("b"),
               nil,
               "b"
             ),
             LocalVariableWriteNode(19...20)((19...20), nil, nil, 0)],
            SplatNode(22...23)(USTAR(22...23)("*"), nil),
            (11...12),
            (23...24)
          ),
          nil,
          (8...10),
          nil
        )],
       nil,
       (0...4),
       (25...28)
     )]
  )
)
