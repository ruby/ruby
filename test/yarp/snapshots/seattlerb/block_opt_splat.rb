ProgramNode(0...17)(
  ScopeNode(0...0)([]),
  StatementsNode(0...17)(
    [CallNode(0...17)(
       nil,
       nil,
       IDENTIFIER(0...1)("a"),
       nil,
       nil,
       nil,
       BlockNode(2...17)(
         ScopeNode(2...3)([IDENTIFIER(5...6)("b"), IDENTIFIER(13...14)("c")]),
         BlockParametersNode(4...15)(
           ParametersNode(5...14)(
             [],
             [OptionalParameterNode(5...10)(
                IDENTIFIER(5...6)("b"),
                EQUAL(7...8)("="),
                IntegerNode(9...10)()
              )],
             [],
             RestParameterNode(12...14)(
               USTAR(12...13)("*"),
               IDENTIFIER(13...14)("c")
             ),
             [],
             nil,
             nil
           ),
           [],
           (4...5),
           (14...15)
         ),
         nil,
         (2...3),
         (16...17)
       ),
       "a"
     )]
  )
)
