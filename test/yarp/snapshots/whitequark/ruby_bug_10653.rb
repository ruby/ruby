ProgramNode(6...93)(
  ScopeNode(0...0)([]),
  StatementsNode(6...93)(
    [IfNode(6...33)(
       QUESTION_MARK(6...7)("?"),
       FalseNode(0...5)(),
       StatementsNode(8...20)(
         [CallNode(8...20)(
            nil,
            nil,
            IDENTIFIER(8...13)("raise"),
            nil,
            nil,
            nil,
            BlockNode(14...20)(
              ScopeNode(14...16)([]),
              nil,
              nil,
              (14...16),
              (17...20)
            ),
            "raise"
          )]
       ),
       ElseNode(21...33)(
         COLON(21...22)(":"),
         StatementsNode(23...33)(
           [CallNode(23...33)(
              nil,
              nil,
              IDENTIFIER(23...26)("tap"),
              nil,
              nil,
              nil,
              BlockNode(27...33)(
                ScopeNode(27...29)([]),
                nil,
                nil,
                (27...29),
                (30...33)
              ),
              "tap"
            )]
         ),
         nil
       ),
       nil
     ),
     IfNode(41...60)(
       QUESTION_MARK(41...42)("?"),
       FalseNode(35...40)(),
       StatementsNode(43...51)(
         [CallNode(43...51)(
            nil,
            nil,
            IDENTIFIER(43...48)("raise"),
            nil,
            nil,
            nil,
            BlockNode(49...51)(
              ScopeNode(49...50)([]),
              nil,
              nil,
              (49...50),
              (50...51)
            ),
            "raise"
          )]
       ),
       ElseNode(52...60)(
         COLON(52...53)(":"),
         StatementsNode(54...60)(
           [CallNode(54...60)(
              nil,
              nil,
              IDENTIFIER(54...57)("tap"),
              nil,
              nil,
              nil,
              BlockNode(58...60)(
                ScopeNode(58...59)([]),
                nil,
                nil,
                (58...59),
                (59...60)
              ),
              "tap"
            )]
         ),
         nil
       ),
       nil
     ),
     IfNode(67...93)(
       QUESTION_MARK(67...68)("?"),
       TrueNode(62...66)(),
       StatementsNode(69...89)(
         [CallNode(69...89)(
            IntegerNode(69...70)(),
            DOT(70...71)("."),
            IDENTIFIER(71...74)("tap"),
            nil,
            nil,
            nil,
            BlockNode(75...89)(
              ScopeNode(75...77)([IDENTIFIER(79...80)("n")]),
              BlockParametersNode(78...81)(
                ParametersNode(79...80)(
                  [RequiredParameterNode(79...80)()],
                  [],
                  [],
                  nil,
                  [],
                  nil,
                  nil
                ),
                [],
                (78...79),
                (80...81)
              ),
              StatementsNode(82...85)(
                [CallNode(82...85)(
                   nil,
                   nil,
                   IDENTIFIER(82...83)("p"),
                   nil,
                   ArgumentsNode(84...85)([LocalVariableReadNode(84...85)(0)]),
                   nil,
                   nil,
                   "p"
                 )]
              ),
              (75...77),
              (86...89)
            ),
            "tap"
          )]
       ),
       ElseNode(90...93)(
         COLON(90...91)(":"),
         StatementsNode(92...93)([IntegerNode(92...93)()]),
         nil
       ),
       nil
     )]
  )
)
