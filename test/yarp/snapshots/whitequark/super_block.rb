ProgramNode(0...35)(
  ScopeNode(0...0)([]),
  StatementsNode(0...35)(
    [ForwardingSuperNode(0...12)(
       BlockNode(6...12)(ScopeNode(6...8)([]), nil, nil, (6...8), (9...12))
     ),
     SuperNode(14...35)(
       KEYWORD_SUPER(14...19)("super"),
       nil,
       ArgumentsNode(20...28)(
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
          CallNode(25...28)(
            nil,
            nil,
            IDENTIFIER(25...28)("bar"),
            nil,
            nil,
            nil,
            nil,
            "bar"
          )]
       ),
       nil,
       BlockNode(29...35)(
         ScopeNode(29...31)([]),
         nil,
         nil,
         (29...31),
         (32...35)
       )
     )]
  )
)
