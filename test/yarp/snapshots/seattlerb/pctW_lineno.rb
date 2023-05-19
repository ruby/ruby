ProgramNode(0...28)(
  ScopeNode(0...0)([]),
  StatementsNode(0...28)(
    [ArrayNode(0...28)(
       [StringNode(3...7)(
          nil,
          STRING_CONTENT(3...7)("a\\nb"),
          nil,
          "a\n" + "b"
        ),
        StringNode(8...9)(nil, STRING_CONTENT(8...9)("c"), nil, "c"),
        StringNode(10...11)(nil, STRING_CONTENT(10...11)("d"), nil, "d"),
        StringNode(12...16)(
          nil,
          STRING_CONTENT(12...16)("e\\\n" + "f"),
          nil,
          "e\n" + "f"
        ),
        StringNode(17...19)(nil, STRING_CONTENT(17...19)("gy"), nil, "gy"),
        StringNode(20...23)(nil, STRING_CONTENT(20...23)("h\\y"), nil, "hy"),
        StringNode(24...27)(nil, STRING_CONTENT(24...27)("i\\y"), nil, "iy")],
       PERCENT_UPPER_W(0...3)("%W("),
       STRING_END(27...28)(")")
     )]
  )
)
