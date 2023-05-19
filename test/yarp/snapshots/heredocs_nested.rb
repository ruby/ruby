ProgramNode(0...47)(
  ScopeNode(0...0)([]),
  StatementsNode(0...47)(
    [InterpolatedStringNode(0...47)(
       HEREDOC_START(0...7)("<<~RUBY"),
       [StringNode(8...12)(nil, STRING_CONTENT(8...12)("pre\n"), nil, "pre\n"),
        StringInterpolatedNode(12...36)(
          EMBEXPR_BEGIN(12...14)("\#{"),
          StatementsNode(15...35)(
            [InterpolatedStringNode(15...35)(
               HEREDOC_START(15...21)("<<RUBY"),
               [StringNode(22...30)(
                  nil,
                  STRING_CONTENT(22...30)("  hello\n"),
                  nil,
                  "  hello\n"
                )],
               HEREDOC_END(30...35)("RUBY\n")
             )]
          ),
          EMBEXPR_END(35...36)("}")
        ),
        StringNode(36...42)(
          nil,
          STRING_CONTENT(36...42)("\n" + "post\n"),
          nil,
          "\n" + "post\n"
        )],
       HEREDOC_END(42...47)("RUBY\n")
     )]
  )
)
