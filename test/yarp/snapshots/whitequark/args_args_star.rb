ProgramNode(0...36)(
  ScopeNode(0...0)([]),
  StatementsNode(0...36)(
    [CallNode(0...14)(
       nil,
       nil,
       IDENTIFIER(0...3)("fun"),
       PARENTHESIS_LEFT(3...4)("("),
       ArgumentsNode(4...13)(
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
          SplatNode(9...13)(
            USTAR(9...10)("*"),
            CallNode(10...13)(
              nil,
              nil,
              IDENTIFIER(10...13)("bar"),
              nil,
              nil,
              nil,
              nil,
              "bar"
            )
          )]
       ),
       PARENTHESIS_RIGHT(13...14)(")"),
       nil,
       "fun"
     ),
     CallNode(16...36)(
       nil,
       nil,
       IDENTIFIER(16...19)("fun"),
       PARENTHESIS_LEFT(19...20)("("),
       ArgumentsNode(20...35)(
         [CallNode(20...23)(
            nil,
            nil,
            IDENTIFIER(20...23)("foo"),
            nil,
            nil,
            nil,
            nil,
            "foo"
          ),
          SplatNode(25...29)(
            USTAR(25...26)("*"),
            CallNode(26...29)(
              nil,
              nil,
              IDENTIFIER(26...29)("bar"),
              nil,
              nil,
              nil,
              nil,
              "bar"
            )
          ),
          BlockArgumentNode(31...35)(
            CallNode(32...35)(
              nil,
              nil,
              IDENTIFIER(32...35)("baz"),
              nil,
              nil,
              nil,
              nil,
              "baz"
            ),
            (31...32)
          )]
       ),
       PARENTHESIS_RIGHT(35...36)(")"),
       nil,
       "fun"
     )]
  )
)
