ProgramNode(0...24)(
  [:a],
  StatementsNode(0...24)(
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
     LocalVariableReadNode(10...11)(:a, 0),
     MatchPredicateNode(13...21)(
       IntegerNode(13...14)(),
       ArrayPatternNode(18...21)(
         nil,
         [LocalVariableWriteNode(19...20)(:a, 0, nil, (19...20), nil)],
         nil,
         [],
         (18...19),
         (20...21)
       ),
       (15...17)
     ),
     LocalVariableReadNode(23...24)(:a, 0)]
  )
)
