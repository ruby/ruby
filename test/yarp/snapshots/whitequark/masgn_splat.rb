ProgramNode(0...139)(
  ScopeNode(0...0)(
    [IDENTIFIER(12...13)("c"),
     IDENTIFIER(15...16)("d"),
     IDENTIFIER(25...26)("b"),
     IDENTIFIER(67...68)("a")]
  ),
  StatementsNode(0...139)(
    [MultiWriteNode(0...7)(
       [SplatNode(0...1)(USTAR(0...1)("*"), nil)],
       EQUAL(2...3)("="),
       CallNode(4...7)(
         nil,
         nil,
         IDENTIFIER(4...7)("bar"),
         nil,
         nil,
         nil,
         nil,
         "bar"
       ),
       nil,
       nil
     ),
     MultiWriteNode(9...22)(
       [MultiWriteNode(9...10)(
          [SplatNode(9...10)(USTAR(9...10)("*"), nil)],
          nil,
          nil,
          nil,
          nil
        ),
        LocalVariableWriteNode(12...13)((12...13), nil, nil, 0),
        LocalVariableWriteNode(15...16)((15...16), nil, nil, 0)],
       EQUAL(17...18)("="),
       CallNode(19...22)(
         nil,
         nil,
         IDENTIFIER(19...22)("bar"),
         nil,
         nil,
         nil,
         nil,
         "bar"
       ),
       nil,
       nil
     ),
     MultiWriteNode(24...32)(
       [SplatNode(24...26)(
          USTAR(24...25)("*"),
          LocalVariableWriteNode(25...26)((25...26), nil, nil, 0)
        )],
       EQUAL(27...28)("="),
       CallNode(29...32)(
         nil,
         nil,
         IDENTIFIER(29...32)("bar"),
         nil,
         nil,
         nil,
         nil,
         "bar"
       ),
       nil,
       nil
     ),
     MultiWriteNode(34...45)(
       [MultiWriteNode(34...36)(
          [SplatNode(34...36)(
             USTAR(34...35)("*"),
             LocalVariableWriteNode(35...36)((35...36), nil, nil, 0)
           )],
          nil,
          nil,
          nil,
          nil
        ),
        LocalVariableWriteNode(38...39)((38...39), nil, nil, 0)],
       EQUAL(40...41)("="),
       CallNode(42...45)(
         nil,
         nil,
         IDENTIFIER(42...45)("bar"),
         nil,
         nil,
         nil,
         nil,
         "bar"
       ),
       nil,
       nil
     ),
     MultiWriteNode(47...65)(
       [InstanceVariableWriteNode(47...51)((47...51), nil, nil),
        ClassVariableWriteNode(53...58)((53...58), nil, nil)],
       EQUAL(59...60)("="),
       SplatNode(61...65)(
         USTAR(61...62)("*"),
         CallNode(62...65)(
           nil,
           nil,
           IDENTIFIER(62...65)("foo"),
           nil,
           nil,
           nil,
           nil,
           "foo"
         )
       ),
       nil,
       nil
     ),
     MultiWriteNode(67...77)(
       [LocalVariableWriteNode(67...68)((67...68), nil, nil, 0),
        SplatNode(70...71)(USTAR(70...71)("*"), nil)],
       EQUAL(72...73)("="),
       CallNode(74...77)(
         nil,
         nil,
         IDENTIFIER(74...77)("bar"),
         nil,
         nil,
         nil,
         nil,
         "bar"
       ),
       nil,
       nil
     ),
     MultiWriteNode(79...92)(
       [LocalVariableWriteNode(79...80)((79...80), nil, nil, 0),
        SplatNode(82...83)(USTAR(82...83)("*"), nil),
        LocalVariableWriteNode(85...86)((85...86), nil, nil, 0)],
       EQUAL(87...88)("="),
       CallNode(89...92)(
         nil,
         nil,
         IDENTIFIER(89...92)("bar"),
         nil,
         nil,
         nil,
         nil,
         "bar"
       ),
       nil,
       nil
     ),
     MultiWriteNode(94...105)(
       [LocalVariableWriteNode(94...95)((94...95), nil, nil, 0),
        SplatNode(97...99)(
          USTAR(97...98)("*"),
          LocalVariableWriteNode(98...99)((98...99), nil, nil, 0)
        )],
       EQUAL(100...101)("="),
       CallNode(102...105)(
         nil,
         nil,
         IDENTIFIER(102...105)("bar"),
         nil,
         nil,
         nil,
         nil,
         "bar"
       ),
       nil,
       nil
     ),
     MultiWriteNode(107...121)(
       [LocalVariableWriteNode(107...108)((107...108), nil, nil, 0),
        SplatNode(110...112)(
          USTAR(110...111)("*"),
          LocalVariableWriteNode(111...112)((111...112), nil, nil, 0)
        ),
        LocalVariableWriteNode(114...115)((114...115), nil, nil, 0)],
       EQUAL(116...117)("="),
       CallNode(118...121)(
         nil,
         nil,
         IDENTIFIER(118...121)("bar"),
         nil,
         nil,
         nil,
         nil,
         "bar"
       ),
       nil,
       nil
     ),
     MultiWriteNode(123...139)(
       [LocalVariableWriteNode(123...124)((123...124), nil, nil, 0),
        LocalVariableWriteNode(126...127)((126...127), nil, nil, 0)],
       EQUAL(128...129)("="),
       ArrayNode(0...139)(
         [SplatNode(130...134)(
            USTAR(130...131)("*"),
            CallNode(131...134)(
              nil,
              nil,
              IDENTIFIER(131...134)("foo"),
              nil,
              nil,
              nil,
              nil,
              "foo"
            )
          ),
          CallNode(136...139)(
            nil,
            nil,
            IDENTIFIER(136...139)("bar"),
            nil,
            nil,
            nil,
            nil,
            "bar"
          )],
         nil,
         nil
       ),
       nil,
       nil
     )]
  )
)
