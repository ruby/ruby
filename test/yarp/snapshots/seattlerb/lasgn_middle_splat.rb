ProgramNode(0...12)(
  ScopeNode(0...0)([IDENTIFIER(0...1)("a")]),
  StatementsNode(0...12)(
    [LocalVariableWriteNode(0...12)(
       (0...1),
       ArrayNode(0...12)(
         [CallNode(4...5)(
            nil,
            nil,
            IDENTIFIER(4...5)("b"),
            nil,
            nil,
            nil,
            nil,
            "b"
          ),
          SplatNode(7...9)(
            USTAR(7...8)("*"),
            CallNode(8...9)(
              nil,
              nil,
              IDENTIFIER(8...9)("c"),
              nil,
              nil,
              nil,
              nil,
              "c"
            )
          ),
          CallNode(11...12)(
            nil,
            nil,
            IDENTIFIER(11...12)("d"),
            nil,
            nil,
            nil,
            nil,
            "d"
          )],
         nil,
         nil
       ),
       (2...3),
       0
     )]
  )
)
