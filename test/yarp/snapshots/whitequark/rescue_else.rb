ProgramNode(0...40)(
  ScopeNode(0...0)([]),
  StatementsNode(0...40)(
    [BeginNode(0...40)(
       KEYWORD_BEGIN(0...5)("begin"),
       StatementsNode(7...11)(
         [CallNode(7...11)(
            nil,
            nil,
            IDENTIFIER(7...11)("meth"),
            nil,
            nil,
            nil,
            nil,
            "meth"
          )]
       ),
       RescueNode(13...24)(
         KEYWORD_RESCUE(13...19)("rescue"),
         [],
         nil,
         nil,
         StatementsNode(21...24)(
           [CallNode(21...24)(
              nil,
              nil,
              IDENTIFIER(21...24)("foo"),
              nil,
              nil,
              nil,
              nil,
              "foo"
            )]
         ),
         nil
       ),
       ElseNode(26...40)(
         KEYWORD_ELSE(26...30)("else"),
         StatementsNode(32...35)(
           [CallNode(32...35)(
              nil,
              nil,
              IDENTIFIER(32...35)("bar"),
              nil,
              nil,
              nil,
              nil,
              "bar"
            )]
         ),
         KEYWORD_END(37...40)("end")
       ),
       nil,
       KEYWORD_END(37...40)("end")
     )]
  )
)
