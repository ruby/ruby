ProgramNode(0...33)(
  ScopeNode(0...0)([]),
  StatementsNode(0...33)(
    [CaseNode(0...33)(
       HashNode(5...11)(
         BRACE_LEFT(5...6)("{"),
         [AssocNode(6...10)(
            SymbolNode(6...8)(
              nil,
              LABEL(6...7)("a"),
              LABEL_END(7...8)(":"),
              "a"
            ),
            IntegerNode(9...10)(),
            nil
          )],
         BRACE_RIGHT(10...11)("}")
       ),
       [InNode(12...29)(
          HashPatternNode(15...23)(
            nil,
            [AssocNode(16...18)(
               SymbolNode(16...18)(
                 nil,
                 LABEL(16...17)("a"),
                 LABEL_END(17...18)(":"),
                 "a"
               ),
               nil,
               nil
             ),
             AssocSplatNode(20...22)(nil, (20...22))],
            nil,
            (15...16),
            (22...23)
          ),
          StatementsNode(26...29)(
            [ArrayNode(26...29)(
               [CallNode(27...28)(
                  nil,
                  nil,
                  IDENTIFIER(27...28)("a"),
                  nil,
                  nil,
                  nil,
                  nil,
                  "a"
                )],
               BRACKET_LEFT_ARRAY(26...27)("["),
               BRACKET_RIGHT(28...29)("]")
             )]
          ),
          (12...14),
          nil
        )],
       nil,
       (0...4),
       (30...33)
     )]
  )
)
