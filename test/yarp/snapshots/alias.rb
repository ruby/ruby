ProgramNode(0...199)(
  ScopeNode(0...0)([]),
  StatementsNode(0...199)(
    [AliasNode(0...15)(
       SymbolNode(6...10)(
         SYMBOL_BEGIN(6...7)(":"),
         IDENTIFIER(7...10)("foo"),
         nil,
         "foo"
       ),
       SymbolNode(11...15)(
         SYMBOL_BEGIN(11...12)(":"),
         IDENTIFIER(12...15)("bar"),
         nil,
         "bar"
       ),
       (0...5)
     ),
     AliasNode(17...38)(
       SymbolNode(23...30)(
         SYMBOL_BEGIN(23...26)("%s["),
         STRING_CONTENT(26...29)("abc"),
         STRING_END(29...30)("]"),
         "abc"
       ),
       SymbolNode(31...38)(
         SYMBOL_BEGIN(31...34)("%s["),
         STRING_CONTENT(34...37)("def"),
         STRING_END(37...38)("]"),
         "def"
       ),
       (17...22)
     ),
     AliasNode(40...59)(
       SymbolNode(46...52)(
         SYMBOL_BEGIN(46...48)(":'"),
         STRING_CONTENT(48...51)("abc"),
         STRING_END(51...52)("'"),
         "abc"
       ),
       SymbolNode(53...59)(
         SYMBOL_BEGIN(53...55)(":'"),
         STRING_CONTENT(55...58)("def"),
         STRING_END(58...59)("'"),
         "def"
       ),
       (40...45)
     ),
     AliasNode(61...84)(
       InterpolatedSymbolNode(67...77)(
         SYMBOL_BEGIN(67...69)(":\""),
         [StringNode(69...72)(nil, STRING_CONTENT(69...72)("abc"), nil, "abc"),
          StringInterpolatedNode(72...76)(
            EMBEXPR_BEGIN(72...74)("\#{"),
            StatementsNode(74...75)([IntegerNode(74...75)()]),
            EMBEXPR_END(75...76)("}")
          )],
         STRING_END(76...77)("\"")
       ),
       SymbolNode(78...84)(
         SYMBOL_BEGIN(78...80)(":'"),
         STRING_CONTENT(80...83)("def"),
         STRING_END(83...84)("'"),
         "def"
       ),
       (61...66)
     ),
     AliasNode(86...97)(
       GlobalVariableReadNode(92...94)(GLOBAL_VARIABLE(92...94)("$a")),
       GlobalVariableReadNode(95...97)(BACK_REFERENCE(95...97)("$'")),
       (86...91)
     ),
     AliasNode(99...112)(
       SymbolNode(105...108)(nil, IDENTIFIER(105...108)("foo"), nil, "foo"),
       SymbolNode(109...112)(nil, IDENTIFIER(109...112)("bar"), nil, "bar"),
       (99...104)
     ),
     AliasNode(114...129)(
       GlobalVariableReadNode(120...124)(GLOBAL_VARIABLE(120...124)("$foo")),
       GlobalVariableReadNode(125...129)(GLOBAL_VARIABLE(125...129)("$bar")),
       (114...119)
     ),
     AliasNode(131...143)(
       SymbolNode(137...140)(nil, IDENTIFIER(137...140)("foo"), nil, "foo"),
       SymbolNode(141...143)(nil, KEYWORD_IF(141...143)("if"), nil, "if"),
       (131...136)
     ),
     AliasNode(145...158)(
       SymbolNode(151...154)(nil, IDENTIFIER(151...154)("foo"), nil, "foo"),
       SymbolNode(155...158)(
         nil,
         LESS_EQUAL_GREATER(155...158)("<=>"),
         nil,
         "<=>"
       ),
       (145...150)
     ),
     AliasNode(160...175)(
       SymbolNode(166...169)(
         SYMBOL_BEGIN(166...167)(":"),
         EQUAL_EQUAL(167...169)("=="),
         nil,
         "=="
       ),
       SymbolNode(170...175)(
         SYMBOL_BEGIN(170...171)(":"),
         IDENTIFIER(171...175)("eql?"),
         nil,
         "eql?"
       ),
       (160...165)
     ),
     AliasNode(177...186)(
       SymbolNode(183...184)(nil, CONSTANT(183...184)("A"), nil, "A"),
       SymbolNode(185...186)(nil, CONSTANT(185...186)("B"), nil, "B"),
       (177...182)
     ),
     AliasNode(188...199)(
       SymbolNode(194...196)(
         SYMBOL_BEGIN(194...195)(":"),
         CONSTANT(195...196)("A"),
         nil,
         "A"
       ),
       SymbolNode(197...199)(
         SYMBOL_BEGIN(197...198)(":"),
         CONSTANT(198...199)("B"),
         nil,
         "B"
       ),
       (188...193)
     )]
  )
)
