ProgramNode(0...25)(
  ScopeNode(0...0)([]),
  StatementsNode(0...25)(
    [RegularExpressionNode(0...15)(
       REGEXP_BEGIN(0...1)("/"),
       STRING_CONTENT(1...14)("\\u{c0de babe}"),
       REGEXP_END(14...15)("/"),
       "샞몾"
     ),
     RegularExpressionNode(17...25)(
       REGEXP_BEGIN(17...18)("/"),
       STRING_CONTENT(18...24)("\\u{df}"),
       REGEXP_END(24...25)("/"),
       "ß"
     )]
  )
)
