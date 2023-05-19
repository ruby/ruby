ProgramNode(0...20)(
  ScopeNode(0...0)([]),
  StatementsNode(0...20)(
    [InterpolatedStringNode(0...20)(
       STRING_BEGIN(0...2)("%{"),
       [StringNode(2...5)(nil, STRING_CONTENT(2...5)(" { "), nil, " { "),
        StringInterpolatedNode(5...16)(
          EMBEXPR_BEGIN(5...7)("\#{"),
          StatementsNode(8...14)(
            [InterpolatedStringNode(8...14)(
               STRING_BEGIN(8...9)("\""),
               [StringInterpolatedNode(9...13)(
                  EMBEXPR_BEGIN(9...11)("\#{"),
                  StatementsNode(11...12)([IntegerNode(11...12)()]),
                  EMBEXPR_END(12...13)("}")
                )],
               STRING_END(13...14)("\"")
             )]
          ),
          EMBEXPR_END(15...16)("}")
        ),
        StringNode(16...19)(nil, STRING_CONTENT(16...19)(" } "), nil, " } ")],
       STRING_END(19...20)("}")
     )]
  )
)
