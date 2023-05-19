ProgramNode(0...66)(
  ScopeNode(0...0)([]),
  StatementsNode(0...66)(
    [InterpolatedStringNode(0...22)(
       HEREDOC_START(0...8)("<<'HERE'"),
       [StringNode(9...17)(
          nil,
          STRING_CONTENT(9...17)("foo\n" + "bar\n"),
          nil,
          "foo\n" + "bar\n"
        )],
       HEREDOC_END(17...22)("HERE\n")
     ),
     InterpolatedStringNode(23...43)(
       HEREDOC_START(23...29)("<<HERE"),
       [StringNode(30...38)(
          nil,
          STRING_CONTENT(30...38)("foo\n" + "bar\n"),
          nil,
          "foo\n" + "bar\n"
        )],
       HEREDOC_END(38...43)("HERE\n")
     ),
     InterpolatedXStringNode(44...66)(
       HEREDOC_START(44...52)("<<`HERE`"),
       [StringNode(53...61)(
          nil,
          STRING_CONTENT(53...61)("foo\n" + "bar\n"),
          nil,
          "foo\n" + "bar\n"
        )],
       HEREDOC_END(61...66)("HERE\n")
     )]
  )
)
