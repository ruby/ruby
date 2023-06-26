ProgramNode(0...51)(
  [:a, :foo],
  StatementsNode(0...51)(
    [MatchRequiredNode(0...8)(
       IntegerNode(0...1)(),
       ArrayPatternNode(5...8)(
         nil,
         [LocalVariableWriteNode(6...7)(:a, 0, nil, (6...7), nil)],
         nil,
         [],
         (5...6),
         (7...8)
       ),
       (2...4)
     ),
     MatchRequiredNode(9...17)(
       IntegerNode(9...10)(),
       ArrayPatternNode(14...17)(
         nil,
         [],
         SplatNode(15...16)((15...16), nil),
         [],
         (14...15),
         (16...17)
       ),
       (11...13)
     ),
     MatchPredicateNode(18...33)(
       IntegerNode(18...19)(),
       FindPatternNode(23...33)(
         nil,
         SplatNode(24...25)((24...25), nil),
         [IntegerNode(27...29)()],
         SplatNode(31...32)((31...32), nil),
         (23...24),
         (32...33)
       ),
       (20...22)
     ),
     MatchPredicateNode(34...51)(
       IntegerNode(34...35)(),
       FindPatternNode(39...51)(
         nil,
         SplatNode(40...41)((40...41), nil),
         [LocalVariableWriteNode(43...44)(:a, 0, nil, (43...44), nil)],
         SplatNode(46...50)(
           (46...47),
           LocalVariableWriteNode(47...50)(:foo, 0, nil, (47...50), nil)
         ),
         (39...40),
         (50...51)
       ),
       (36...38)
     )]
  )
)
