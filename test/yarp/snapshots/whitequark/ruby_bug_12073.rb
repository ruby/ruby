ProgramNode(0...49)(
  ScopeNode(0...0)([IDENTIFIER(0...1)("a")]),
  StatementsNode(0...49)(
    [LocalVariableWriteNode(0...5)((0...1), IntegerNode(4...5)(), (2...3), 0),
     CallNode(7...13)(
       nil,
       nil,
       IDENTIFIER(7...8)("a"),
       nil,
       ArgumentsNode(9...13)(
         [HashNode(9...13)(
            nil,
            [AssocNode(9...13)(
               SymbolNode(9...11)(
                 nil,
                 LABEL(9...10)("b"),
                 LABEL_END(10...11)(":"),
                 "b"
               ),
               IntegerNode(12...13)(),
               nil
             )],
            nil
          )]
       ),
       nil,
       nil,
       "a"
     ),
     DefNode(15...49)(
       IDENTIFIER(19...22)("foo"),
       nil,
       ParametersNode(23...28)(
         [RequiredParameterNode(23...28)()],
         [],
         [],
         nil,
         [],
         nil,
         nil
       ),
       StatementsNode(30...44)(
         [CallNode(30...44)(
            nil,
            nil,
            IDENTIFIER(30...35)("raise"),
            nil,
            ArgumentsNode(36...44)(
              [ConstantPathNode(36...40)(
                 ConstantReadNode(36...37)(),
                 ConstantReadNode(39...40)(),
                 (37...39)
               ),
               StringNode(42...44)(
                 STRING_BEGIN(42...43)("'"),
                 STRING_CONTENT(43...43)(""),
                 STRING_END(43...44)("'"),
                 ""
               )]
            ),
            nil,
            nil,
            "raise"
          )]
       ),
       ScopeNode(15...18)([IDENTIFIER(23...28)("raise")]),
       (15...18),
       nil,
       nil,
       nil,
       nil,
       (46...49)
     )]
  )
)
