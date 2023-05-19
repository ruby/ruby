ProgramNode(0...28)(
  ScopeNode(0...0)([]),
  StatementsNode(0...28)(
    [DefNode(0...28)(
       IDENTIFIER(4...5)("f"),
       nil,
       ParametersNode(6...16)(
         [],
         [],
         [],
         nil,
         [KeywordParameterNode(6...12)(LABEL(6...8)("a:"), NilNode(9...12)())],
         KeywordRestParameterNode(14...16)(USTAR_STAR(14...16)("**"), nil),
         nil
       ),
       StatementsNode(19...24)(
         [CallNode(19...24)(
            nil,
            nil,
            IDENTIFIER(19...20)("b"),
            PARENTHESIS_LEFT(20...21)("("),
            ArgumentsNode(21...23)(
              [HashNode(21...23)(
                 nil,
                 [AssocSplatNode(21...23)(nil, (21...23))],
                 nil
               )]
            ),
            PARENTHESIS_RIGHT(23...24)(")"),
            nil,
            "b"
          )]
       ),
       ScopeNode(0...3)([LABEL(6...7)("a"), USTAR_STAR(14...16)("**")]),
       (0...3),
       nil,
       (5...6),
       (16...17),
       nil,
       (25...28)
     )]
  )
)
