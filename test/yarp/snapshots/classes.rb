ProgramNode(0...370)(
  ScopeNode(0...0)([]),
  StatementsNode(0...370)(
    [ClassNode(0...17)(
       ScopeNode(0...5)([IDENTIFIER(8...9)("a")]),
       KEYWORD_CLASS(0...5)("class"),
       ConstantReadNode(6...7)(),
       nil,
       nil,
       StatementsNode(8...13)(
         [LocalVariableWriteNode(8...13)(
            (8...9),
            IntegerNode(12...13)(),
            (10...11),
            0
          )]
       ),
       KEYWORD_END(14...17)("end")
     ),
     ClassNode(19...39)(
       ScopeNode(19...24)([]),
       KEYWORD_CLASS(19...24)("class"),
       ConstantReadNode(25...26)(),
       nil,
       nil,
       BeginNode(0...39)(
         nil,
         nil,
         nil,
         nil,
         EnsureNode(28...39)(
           KEYWORD_ENSURE(28...34)("ensure"),
           nil,
           KEYWORD_END(36...39)("end")
         ),
         KEYWORD_END(36...39)("end")
       ),
       KEYWORD_END(36...39)("end")
     ),
     ClassNode(41...75)(
       ScopeNode(41...46)([]),
       KEYWORD_CLASS(41...46)("class"),
       ConstantReadNode(47...48)(),
       nil,
       nil,
       BeginNode(0...75)(
         nil,
         nil,
         RescueNode(50...56)(
           KEYWORD_RESCUE(50...56)("rescue"),
           [],
           nil,
           nil,
           nil,
           nil
         ),
         ElseNode(58...70)(
           KEYWORD_ELSE(58...62)("else"),
           nil,
           KEYWORD_ENSURE(64...70)("ensure")
         ),
         EnsureNode(64...75)(
           KEYWORD_ENSURE(64...70)("ensure"),
           nil,
           KEYWORD_END(72...75)("end")
         ),
         KEYWORD_END(72...75)("end")
       ),
       KEYWORD_END(72...75)("end")
     ),
     ClassNode(77...98)(
       ScopeNode(77...82)([IDENTIFIER(89...90)("a")]),
       KEYWORD_CLASS(77...82)("class"),
       ConstantReadNode(83...84)(),
       LESS(85...86)("<"),
       ConstantReadNode(87...88)(),
       StatementsNode(89...94)(
         [LocalVariableWriteNode(89...94)(
            (89...90),
            IntegerNode(93...94)(),
            (91...92),
            0
          )]
       ),
       KEYWORD_END(95...98)("end")
     ),
     SingletonClassNode(100...120)(
       ScopeNode(100...105)([]),
       KEYWORD_CLASS(100...105)("class"),
       LESS_LESS(106...108)("<<"),
       CallNode(109...116)(
         CallNode(113...116)(
           nil,
           nil,
           IDENTIFIER(113...116)("foo"),
           nil,
           nil,
           nil,
           nil,
           "foo"
         ),
         nil,
         KEYWORD_NOT(109...112)("not"),
         nil,
         nil,
         nil,
         nil,
         "!"
       ),
       nil,
       KEYWORD_END(117...120)("end")
     ),
     ClassNode(122...162)(
       ScopeNode(122...127)([]),
       KEYWORD_CLASS(122...127)("class"),
       ConstantReadNode(128...129)(),
       nil,
       nil,
       StatementsNode(131...157)(
         [SingletonClassNode(131...157)(
            ScopeNode(131...136)([]),
            KEYWORD_CLASS(131...136)("class"),
            LESS_LESS(137...139)("<<"),
            SelfNode(140...144)(),
            BeginNode(0...157)(
              nil,
              nil,
              nil,
              nil,
              EnsureNode(146...157)(
                KEYWORD_ENSURE(146...152)("ensure"),
                nil,
                KEYWORD_END(154...157)("end")
              ),
              KEYWORD_END(154...157)("end")
            ),
            KEYWORD_END(154...157)("end")
          )]
       ),
       KEYWORD_END(159...162)("end")
     ),
     ClassNode(164...218)(
       ScopeNode(164...169)([]),
       KEYWORD_CLASS(164...169)("class"),
       ConstantReadNode(170...171)(),
       nil,
       nil,
       StatementsNode(173...213)(
         [SingletonClassNode(173...213)(
            ScopeNode(173...178)([]),
            KEYWORD_CLASS(173...178)("class"),
            LESS_LESS(179...181)("<<"),
            SelfNode(182...186)(),
            BeginNode(0...213)(
              nil,
              nil,
              RescueNode(188...194)(
                KEYWORD_RESCUE(188...194)("rescue"),
                [],
                nil,
                nil,
                nil,
                nil
              ),
              ElseNode(196...208)(
                KEYWORD_ELSE(196...200)("else"),
                nil,
                KEYWORD_ENSURE(202...208)("ensure")
              ),
              EnsureNode(202...213)(
                KEYWORD_ENSURE(202...208)("ensure"),
                nil,
                KEYWORD_END(210...213)("end")
              ),
              KEYWORD_END(210...213)("end")
            ),
            KEYWORD_END(210...213)("end")
          )]
       ),
       KEYWORD_END(215...218)("end")
     ),
     SingletonClassNode(220...240)(
       ScopeNode(220...225)([]),
       KEYWORD_CLASS(220...225)("class"),
       LESS_LESS(226...228)("<<"),
       CallNode(229...236)(
         CallNode(229...232)(
           nil,
           nil,
           IDENTIFIER(229...232)("foo"),
           nil,
           nil,
           nil,
           nil,
           "foo"
         ),
         DOT(232...233)("."),
         IDENTIFIER(233...236)("bar"),
         nil,
         nil,
         nil,
         nil,
         "bar"
       ),
       nil,
       KEYWORD_END(237...240)("end")
     ),
     SingletonClassNode(242...262)(
       ScopeNode(242...247)([]),
       KEYWORD_CLASS(242...247)("class"),
       LESS_LESS(248...250)("<<"),
       CallNode(251...258)(
         CallNode(251...254)(
           nil,
           nil,
           IDENTIFIER(251...254)("foo"),
           nil,
           nil,
           nil,
           nil,
           "foo"
         ),
         DOT(254...255)("."),
         IDENTIFIER(255...258)("bar"),
         nil,
         nil,
         nil,
         nil,
         "bar"
       ),
       nil,
       KEYWORD_END(259...262)("end")
     ),
     SingletonClassNode(264...281)(
       ScopeNode(264...269)([]),
       KEYWORD_CLASS(264...269)("class"),
       LESS_LESS(270...272)("<<"),
       SelfNode(273...277)(),
       nil,
       KEYWORD_END(278...281)("end")
     ),
     SingletonClassNode(283...300)(
       ScopeNode(283...288)([]),
       KEYWORD_CLASS(283...288)("class"),
       LESS_LESS(289...291)("<<"),
       SelfNode(292...296)(),
       nil,
       KEYWORD_END(297...300)("end")
     ),
     SingletonClassNode(302...325)(
       ScopeNode(302...307)([]),
       KEYWORD_CLASS(302...307)("class"),
       LESS_LESS(308...310)("<<"),
       SelfNode(311...315)(),
       StatementsNode(316...321)(
         [CallNode(316...321)(
            IntegerNode(316...317)(),
            nil,
            PLUS(318...319)("+"),
            nil,
            ArgumentsNode(320...321)([IntegerNode(320...321)()]),
            nil,
            nil,
            "+"
          )]
       ),
       KEYWORD_END(322...325)("end")
     ),
     SingletonClassNode(327...350)(
       ScopeNode(327...332)([]),
       KEYWORD_CLASS(327...332)("class"),
       LESS_LESS(333...335)("<<"),
       SelfNode(336...340)(),
       StatementsNode(341...346)(
         [CallNode(341...346)(
            IntegerNode(341...342)(),
            nil,
            PLUS(343...344)("+"),
            nil,
            ArgumentsNode(345...346)([IntegerNode(345...346)()]),
            nil,
            nil,
            "+"
          )]
       ),
       KEYWORD_END(347...350)("end")
     ),
     ClassNode(352...370)(
       ScopeNode(352...357)([]),
       KEYWORD_CLASS(352...357)("class"),
       ConstantReadNode(358...359)(),
       LESS(360...361)("<"),
       CallNode(362...366)(
         ConstantReadNode(362...363)(),
         nil,
         BRACKET_LEFT_RIGHT(363...364)("["),
         BRACKET_LEFT(363...364)("["),
         ArgumentsNode(364...365)([IntegerNode(364...365)()]),
         BRACKET_RIGHT(365...366)("]"),
         nil,
         "[]"
       ),
       nil,
       KEYWORD_END(367...370)("end")
     )]
  )
)
