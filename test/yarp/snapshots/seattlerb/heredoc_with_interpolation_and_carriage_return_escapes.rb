ProgramNode(0...21)(
  ScopeNode(0...0)([]),
  StatementsNode(0...21)(
    [InterpolatedStringNode(0...21)(
       HEREDOC_START(0...5)("<<EOS"),
       [StringNode(6...11)(
          nil,
          STRING_CONTENT(6...11)("foo\\r"),
          nil,
          "foo\r"
        ),
        InstanceVariableReadNode(12...16)(),
        StringNode(16...17)(nil, STRING_CONTENT(16...17)("\n"), nil, "\n")],
       HEREDOC_END(17...21)("EOS\n")
     )]
  )
)
