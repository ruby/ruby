ProgramNode(0...26)(
  ScopeNode(0...0)([]),
  StatementsNode(0...26)(
    [InterpolatedStringNode(0...26)(
       STRING_BEGIN(0...3)("%Q["),
       [StringNode(3...11)(
          nil,
          STRING_CONTENT(3...11)("before ["),
          nil,
          "before ["
        ),
        StringInterpolatedNode(11...18)(
          EMBEXPR_BEGIN(11...13)("\#{"),
          StatementsNode(13...17)(
            [CallNode(13...17)(
               nil,
               nil,
               IDENTIFIER(13...17)("nest"),
               nil,
               nil,
               nil,
               nil,
               "nest"
             )]
          ),
          EMBEXPR_END(17...18)("}")
        ),
        StringNode(18...25)(
          nil,
          STRING_CONTENT(18...25)("] after"),
          nil,
          "] after"
        )],
       STRING_END(25...26)("]")
     )]
  )
)
