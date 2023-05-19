ProgramNode(0...210)(
  ScopeNode(0...0)([]),
  StatementsNode(0...210)(
    [StringNode(0...6)(
       STRING_BEGIN(0...1)("\""),
       STRING_CONTENT(1...5)("a\\\n" + "b"),
       STRING_END(5...6)("\""),
       "a\n" + "b"
     ),
     ArrayNode(8...16)(
       [SymbolNode(11...15)(
          nil,
          STRING_CONTENT(11...15)("a\\\n" + "b"),
          nil,
          "a\n" + "b"
        )],
       PERCENT_UPPER_I(8...11)("%I{"),
       STRING_END(15...16)("}")
     ),
     StringNode(18...26)(
       STRING_BEGIN(18...21)("%Q{"),
       STRING_CONTENT(21...25)("a\\\n" + "b"),
       STRING_END(25...26)("}"),
       "a\n" + "b"
     ),
     ArrayNode(28...36)(
       [StringNode(31...35)(
          nil,
          STRING_CONTENT(31...35)("a\\\n" + "b"),
          nil,
          "a\n" + "b"
        )],
       PERCENT_UPPER_W(28...31)("%W{"),
       STRING_END(35...36)("}")
     ),
     ArrayNode(38...46)(
       [SymbolNode(41...45)(
          nil,
          STRING_CONTENT(41...45)("a\\\n" + "b"),
          nil,
          "a\n" + "b"
        )],
       PERCENT_LOWER_I(38...41)("%i{"),
       STRING_END(45...46)("}")
     ),
     StringNode(48...56)(
       STRING_BEGIN(48...51)("%q{"),
       STRING_CONTENT(51...55)("a\\\n" + "b"),
       STRING_END(55...56)("}"),
       "a\\\n" + "b"
     ),
     RegularExpressionNode(58...66)(
       REGEXP_BEGIN(58...61)("%r{"),
       STRING_CONTENT(61...65)("a\\\n" + "b"),
       REGEXP_END(65...66)("}"),
       "a\n" + "b"
     ),
     SymbolNode(68...76)(
       SYMBOL_BEGIN(68...71)("%s{"),
       STRING_CONTENT(71...75)("a\\\n" + "b"),
       STRING_END(75...76)("}"),
       "a\n" + "b"
     ),
     ArrayNode(78...86)(
       [StringNode(81...85)(
          nil,
          STRING_CONTENT(81...85)("a\\\n" + "b"),
          nil,
          "a\n" + "b"
        )],
       PERCENT_LOWER_W(78...81)("%w{"),
       STRING_END(85...86)("}")
     ),
     XStringNode(88...96)(
       PERCENT_LOWER_X(88...91)("%x{"),
       STRING_CONTENT(91...95)("a\\\n" + "b"),
       STRING_END(95...96)("}"),
       "a\n" + "b"
     ),
     StringNode(98...105)(
       STRING_BEGIN(98...100)("%{"),
       STRING_CONTENT(100...104)("a\\\n" + "b"),
       STRING_END(104...105)("}"),
       "a\n" + "b"
     ),
     StringNode(107...113)(
       STRING_BEGIN(107...108)("'"),
       STRING_CONTENT(108...112)("a\\\n" + "b"),
       STRING_END(112...113)("'"),
       "a\\\n" + "b"
     ),
     RegularExpressionNode(115...121)(
       REGEXP_BEGIN(115...116)("/"),
       STRING_CONTENT(116...120)("a\\\n" + "b"),
       REGEXP_END(120...121)("/"),
       "a\n" + "b"
     ),
     InterpolatedSymbolNode(123...130)(
       SYMBOL_BEGIN(123...125)(":\""),
       [StringNode(125...129)(
          nil,
          STRING_CONTENT(125...129)("a\\\n" + "b"),
          nil,
          "a\n" + "b"
        )],
       STRING_END(129...130)("\"")
     ),
     SymbolNode(132...139)(
       SYMBOL_BEGIN(132...134)(":'"),
       STRING_CONTENT(134...138)("a\\\n" + "b"),
       STRING_END(138...139)("'"),
       "a\n" + "b"
     ),
     InterpolatedStringNode(141...161)(
       HEREDOC_START(141...150)("<<-\"HERE\""),
       [StringNode(151...156)(
          nil,
          STRING_CONTENT(151...156)("a\\\n" + "b\n"),
          nil,
          "a\n" + "b\n"
        )],
       HEREDOC_END(156...161)("HERE\n")
     ),
     InterpolatedStringNode(162...182)(
       HEREDOC_START(162...171)("<<-'HERE'"),
       [StringNode(172...177)(
          nil,
          STRING_CONTENT(172...177)("a\\\n" + "b\n"),
          nil,
          "a\\\n" + "b\n"
        )],
       HEREDOC_END(177...182)("HERE\n")
     ),
     InterpolatedXStringNode(183...203)(
       HEREDOC_START(183...192)("<<-`HERE`"),
       [StringNode(193...198)(
          nil,
          STRING_CONTENT(193...198)("a\\\n" + "b\n"),
          nil,
          "a\n" + "b\n"
        )],
       HEREDOC_END(198...203)("HERE\n")
     ),
     XStringNode(204...210)(
       BACKTICK(204...205)("`"),
       STRING_CONTENT(205...209)("a\\\n" + "b"),
       STRING_END(209...210)("`"),
       "a\n" + "b"
     )]
  )
)
