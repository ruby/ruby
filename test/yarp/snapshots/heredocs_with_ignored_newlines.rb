ProgramNode(0...106)(
  ScopeNode(0...0)([]),
  StatementsNode(0...106)(
    [InterpolatedStringNode(0...14)(
       HEREDOC_START(0...7)("<<-HERE"),
       [],
       HEREDOC_END(9...14)("HERE\n")
     ),
     InterpolatedStringNode(15...106)(
       HEREDOC_START(15...23)("<<~THERE"),
       [StringNode(25...100)(
          nil,
          STRING_CONTENT(25...100)(
            "  way over\n" +
            "  <<HERE\n" +
            "    not here\n" +
            "  HERE\n" +
            "\n" +
            "  <<~BUT\\\n" +
            "    but\n" +
            "  BUT\n" +
            "    there\n"
          ),
          nil,
          "way over\n" +
          "<<HERE\n" +
          "  not here\n" +
          "HERE\n" +
          "\n" +
          "<<~BUT\n" +
          "  but\n" +
          "BUT\n" +
          "  there\n"
        )],
       HEREDOC_END(100...106)("THERE\n")
     )]
  )
)
