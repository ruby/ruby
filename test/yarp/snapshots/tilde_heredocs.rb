ProgramNode(0...387)(
  ScopeNode(0...0)([]),
  StatementsNode(0...387)(
    [InterpolatedStringNode(0...15)(
       HEREDOC_START(0...6)("<<~EOF"),
       [StringNode(7...11)(nil, STRING_CONTENT(7...11)("  a\n"), nil, "a\n")],
       HEREDOC_END(11...15)("EOF\n")
     ),
     InterpolatedStringNode(16...38)(
       HEREDOC_START(16...22)("<<~EOF"),
       [StringNode(23...34)(
          nil,
          STRING_CONTENT(23...34)("\ta\n" + "  b\n" + "\t\tc\n"),
          nil,
          "\ta\n" + "b\n" + "\t\tc\n"
        )],
       HEREDOC_END(34...38)("EOF\n")
     ),
     InterpolatedStringNode(39...59)(
       HEREDOC_START(39...45)("<<~EOF"),
       [StringNode(46...48)(nil, STRING_CONTENT(46...48)("  "), nil, ""),
        StringInterpolatedNode(48...52)(
          EMBEXPR_BEGIN(48...50)("\#{"),
          StatementsNode(50...51)([IntegerNode(50...51)()]),
          EMBEXPR_END(51...52)("}")
        ),
        StringNode(52...55)(
          nil,
          STRING_CONTENT(52...55)(" a\n"),
          nil,
          " a\n"
        )],
       HEREDOC_END(55...59)("EOF\n")
     ),
     InterpolatedStringNode(60...80)(
       HEREDOC_START(60...66)("<<~EOF"),
       [StringNode(67...71)(nil, STRING_CONTENT(67...71)("  a "), nil, "a "),
        StringInterpolatedNode(71...75)(
          EMBEXPR_BEGIN(71...73)("\#{"),
          StatementsNode(73...74)([IntegerNode(73...74)()]),
          EMBEXPR_END(74...75)("}")
        ),
        StringNode(75...76)(nil, STRING_CONTENT(75...76)("\n"), nil, "\n")],
       HEREDOC_END(76...80)("EOF\n")
     ),
     InterpolatedStringNode(81...102)(
       HEREDOC_START(81...87)("<<~EOF"),
       [StringNode(88...93)(
          nil,
          STRING_CONTENT(88...93)("  a\n" + " "),
          nil,
          " a\n"
        ),
        StringInterpolatedNode(93...97)(
          EMBEXPR_BEGIN(93...95)("\#{"),
          StatementsNode(95...96)([IntegerNode(95...96)()]),
          EMBEXPR_END(96...97)("}")
        ),
        StringNode(97...98)(nil, STRING_CONTENT(97...98)("\n"), nil, "\n")],
       HEREDOC_END(98...102)("EOF\n")
     ),
     InterpolatedStringNode(103...125)(
       HEREDOC_START(103...109)("<<~EOF"),
       [StringNode(110...116)(
          nil,
          STRING_CONTENT(110...116)("  a\n" + "  "),
          nil,
          "a\n"
        ),
        StringInterpolatedNode(116...120)(
          EMBEXPR_BEGIN(116...118)("\#{"),
          StatementsNode(118...119)([IntegerNode(118...119)()]),
          EMBEXPR_END(119...120)("}")
        ),
        StringNode(120...121)(
          nil,
          STRING_CONTENT(120...121)("\n"),
          nil,
          "\n"
        )],
       HEREDOC_END(121...125)("EOF\n")
     ),
     InterpolatedStringNode(126...145)(
       HEREDOC_START(126...132)("<<~EOF"),
       [StringNode(133...141)(
          nil,
          STRING_CONTENT(133...141)("  a\n" + "  b\n"),
          nil,
          "a\n" + "b\n"
        )],
       HEREDOC_END(141...145)("EOF\n")
     ),
     InterpolatedStringNode(146...166)(
       HEREDOC_START(146...152)("<<~EOF"),
       [StringNode(153...162)(
          nil,
          STRING_CONTENT(153...162)("  a\n" + "   b\n"),
          nil,
          "a\n" + " b\n"
        )],
       HEREDOC_END(162...166)("EOF\n")
     ),
     InterpolatedStringNode(167...187)(
       HEREDOC_START(167...173)("<<~EOF"),
       [StringNode(174...183)(
          nil,
          STRING_CONTENT(174...183)("\t\t\ta\n" + "\t\tb\n"),
          nil,
          "\ta\n" + "b\n"
        )],
       HEREDOC_END(183...187)("EOF\n")
     ),
     InterpolatedStringNode(188...210)(
       HEREDOC_START(188...196)("<<~'EOF'"),
       [StringNode(197...206)(
          nil,
          STRING_CONTENT(197...206)("  a \#{1}\n"),
          nil,
          "a \#{1}\n"
        )],
       HEREDOC_END(206...210)("EOF\n")
     ),
     InterpolatedStringNode(211...229)(
       HEREDOC_START(211...217)("<<~EOF"),
       [StringNode(218...225)(
          nil,
          STRING_CONTENT(218...225)("\ta\n" + "\t b\n"),
          nil,
          "a\n" + " b\n"
        )],
       HEREDOC_END(225...229)("EOF\n")
     ),
     InterpolatedStringNode(230...248)(
       HEREDOC_START(230...236)("<<~EOF"),
       [StringNode(237...244)(
          nil,
          STRING_CONTENT(237...244)("\t a\n" + "\tb\n"),
          nil,
          " a\n" + "b\n"
        )],
       HEREDOC_END(244...248)("EOF\n")
     ),
     InterpolatedStringNode(249...275)(
       HEREDOC_START(249...255)("<<~EOF"),
       [StringNode(256...271)(
          nil,
          STRING_CONTENT(256...271)("  \ta\n" + "        b\n"),
          nil,
          "a\n" + "b\n"
        )],
       HEREDOC_END(271...275)("EOF\n")
     ),
     InterpolatedStringNode(276...296)(
       HEREDOC_START(276...282)("<<~EOF"),
       [StringNode(283...292)(
          nil,
          STRING_CONTENT(283...292)("  a\n" + "\n" + "  b\n"),
          nil,
          "a\n" + "\n" + "b\n"
        )],
       HEREDOC_END(292...296)("EOF\n")
     ),
     InterpolatedStringNode(297...317)(
       HEREDOC_START(297...303)("<<~EOF"),
       [StringNode(304...313)(
          nil,
          STRING_CONTENT(304...313)("  a\n" + "\n" + "  b\n"),
          nil,
          "a\n" + "\n" + "b\n"
        )],
       HEREDOC_END(313...317)("EOF\n")
     ),
     InterpolatedStringNode(318...340)(
       HEREDOC_START(318...324)("<<~EOF"),
       [StringNode(325...336)(
          nil,
          STRING_CONTENT(325...336)("  a\n" + "\n" + "\n" + "\n" + "  b\n"),
          nil,
          "a\n" + "\n" + "\n" + "\n" + "b\n"
        )],
       HEREDOC_END(336...340)("EOF\n")
     ),
     InterpolatedStringNode(341...365)(
       HEREDOC_START(341...347)("<<~EOF"),
       [StringNode(348...351)(
          nil,
          STRING_CONTENT(348...351)("\n" + "  "),
          nil,
          "\n"
        ),
        StringInterpolatedNode(351...355)(
          EMBEXPR_BEGIN(351...353)("\#{"),
          StatementsNode(353...354)([IntegerNode(353...354)()]),
          EMBEXPR_END(354...355)("}")
        ),
        StringNode(355...357)(
          nil,
          STRING_CONTENT(355...357)("a\n"),
          nil,
          "a\n"
        )],
       HEREDOC_END(357...365)("    EOF\n")
     ),
     InterpolatedStringNode(366...387)(
       HEREDOC_START(366...372)("<<~EOT"),
       [StringNode(373...375)(nil, STRING_CONTENT(373...375)("  "), nil, ""),
        StringInterpolatedNode(375...379)(
          EMBEXPR_BEGIN(375...377)("\#{"),
          StatementsNode(377...378)([IntegerNode(377...378)()]),
          EMBEXPR_END(378...379)("}")
        ),
        StringNode(379...383)(
          nil,
          STRING_CONTENT(379...383)("\n" + "\tb\n"),
          nil,
          "\n" + "\tb\n"
        )],
       HEREDOC_END(383...387)("EOT\n")
     )]
  )
)
