ProgramNode(0...37)(
  ScopeNode(0...0)([]),
  StatementsNode(0...37)(
    [CaseNode(0...37)(
       CallNode(5...8)(
         nil,
         nil,
         IDENTIFIER(5...8)("foo"),
         nil,
         nil,
         nil,
         nil,
         "foo"
       ),
       [WhenNode(10...32)(
          KEYWORD_WHEN(10...14)("when"),
          [StringNode(15...20)(
             STRING_BEGIN(15...16)("'"),
             STRING_CONTENT(16...19)("bar"),
             STRING_END(19...20)("'"),
             "bar"
           ),
           StringNode(22...27)(
             STRING_BEGIN(22...23)("'"),
             STRING_CONTENT(23...26)("baz"),
             STRING_END(26...27)("'"),
             "baz"
           )],
          StatementsNode(29...32)(
            [CallNode(29...32)(
               nil,
               nil,
               IDENTIFIER(29...32)("bar"),
               nil,
               nil,
               nil,
               nil,
               "bar"
             )]
          )
        )],
       nil,
       (0...4),
       (34...37)
     )]
  )
)
