ProgramNode(0...54)(
  ScopeNode(0...0)([]),
  StatementsNode(0...54)(
    [CallNode(0...2)(
       IntegerNode(1...2)(),
       nil,
       BANG(0...1)("!"),
       nil,
       nil,
       nil,
       nil,
       "!"
     ),
     CallNode(3...8)(
       ParenthesesNode(4...8)(
         StatementsNode(5...7)(
           [CallNode(5...7)(
              IntegerNode(6...7)(),
              nil,
              BANG(5...6)("!"),
              nil,
              nil,
              nil,
              nil,
              "!"
            )]
         ),
         (4...5),
         (7...8)
       ),
       nil,
       BANG(3...4)("!"),
       nil,
       nil,
       nil,
       nil,
       "!"
     ),
     CallNode(9...25)(
       ParenthesesNode(10...25)(
         StatementsNode(11...24)(
           [CallNode(11...24)(
              ParenthesesNode(12...24)(
                StatementsNode(13...23)(
                  [OrNode(13...23)(
                     CallNode(13...16)(
                       nil,
                       nil,
                       IDENTIFIER(13...16)("foo"),
                       nil,
                       nil,
                       nil,
                       nil,
                       "foo"
                     ),
                     CallNode(20...23)(
                       nil,
                       nil,
                       IDENTIFIER(20...23)("bar"),
                       nil,
                       nil,
                       nil,
                       nil,
                       "bar"
                     ),
                     (17...19)
                   )]
                ),
                (12...13),
                (23...24)
              ),
              nil,
              BANG(11...12)("!"),
              nil,
              nil,
              nil,
              nil,
              "!"
            )]
         ),
         (10...11),
         (24...25)
       ),
       nil,
       BANG(9...10)("!"),
       nil,
       nil,
       nil,
       nil,
       "!"
     ),
     CallNode(26...35)(
       CallNode(27...35)(
         ParenthesesNode(27...31)(
           StatementsNode(28...30)(
             [CallNode(28...30)(
                IntegerNode(29...30)(),
                nil,
                BANG(28...29)("!"),
                nil,
                nil,
                nil,
                nil,
                "!"
              )]
           ),
           (27...28),
           (30...31)
         ),
         DOT(31...32)("."),
         IDENTIFIER(32...35)("baz"),
         nil,
         nil,
         nil,
         nil,
         "baz"
       ),
       nil,
       BANG(26...27)("!"),
       nil,
       nil,
       nil,
       nil,
       "!"
     ),
     CallNode(36...38)(
       CallNode(37...38)(
         nil,
         nil,
         IDENTIFIER(37...38)("a"),
         nil,
         nil,
         nil,
         nil,
         "a"
       ),
       nil,
       TILDE(36...37)("~"),
       nil,
       nil,
       nil,
       nil,
       "~"
     ),
     CallNode(39...41)(
       CallNode(40...41)(
         nil,
         nil,
         IDENTIFIER(40...41)("a"),
         nil,
         nil,
         nil,
         nil,
         "a"
       ),
       nil,
       UMINUS(39...40)("-"),
       nil,
       nil,
       nil,
       nil,
       "-@"
     ),
     CallNode(42...44)(
       CallNode(43...44)(
         nil,
         nil,
         IDENTIFIER(43...44)("a"),
         nil,
         nil,
         nil,
         nil,
         "a"
       ),
       nil,
       UPLUS(42...43)("+"),
       nil,
       nil,
       nil,
       nil,
       "+@"
     ),
     CallNode(45...54)(
       CallNode(46...54)(
         ParenthesesNode(46...50)(
           StatementsNode(47...49)(
             [CallNode(47...49)(
                CallNode(48...49)(
                  nil,
                  nil,
                  IDENTIFIER(48...49)("a"),
                  nil,
                  nil,
                  nil,
                  nil,
                  "a"
                ),
                nil,
                UMINUS(47...48)("-"),
                nil,
                nil,
                nil,
                nil,
                "-@"
              )]
           ),
           (46...47),
           (49...50)
         ),
         DOT(50...51)("."),
         IDENTIFIER(51...54)("foo"),
         nil,
         nil,
         nil,
         nil,
         "foo"
       ),
       nil,
       UMINUS(45...46)("-"),
       nil,
       nil,
       nil,
       nil,
       "-@"
     )]
  )
)
