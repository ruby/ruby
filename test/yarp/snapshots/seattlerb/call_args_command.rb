ProgramNode(0...9)(
  ScopeNode(0...0)([]),
  StatementsNode(0...9)(
    [CallNode(0...9)(
       CallNode(0...1)(
         nil,
         nil,
         IDENTIFIER(0...1)("a"),
         nil,
         nil,
         nil,
         nil,
         "a"
       ),
       DOT(1...2)("."),
       IDENTIFIER(2...3)("b"),
       nil,
       ArgumentsNode(4...9)(
         [CallNode(4...9)(
            CallNode(4...5)(
              nil,
              nil,
              IDENTIFIER(4...5)("c"),
              nil,
              nil,
              nil,
              nil,
              "c"
            ),
            DOT(5...6)("."),
            IDENTIFIER(6...7)("d"),
            nil,
            ArgumentsNode(8...9)([IntegerNode(8...9)()]),
            nil,
            nil,
            "d"
          )]
       ),
       nil,
       nil,
       "b"
     )]
  )
)
