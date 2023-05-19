ProgramNode(0...34)(
  ScopeNode(0...0)([IDENTIFIER(5...8)("foo")]),
  StatementsNode(0...34)(
    [MultiWriteNode(0...14)(
       [ConstantPathWriteNode(0...3)(
          ConstantPathNode(0...3)(nil, ConstantReadNode(2...3)(), (0...2)),
          nil,
          nil
        ),
        LocalVariableWriteNode(5...8)((5...8), nil, nil, 0)],
       EQUAL(9...10)("="),
       LocalVariableReadNode(11...14)(0),
       nil,
       nil
     ),
     MultiWriteNode(16...34)(
       [ConstantPathWriteNode(16...23)(
          ConstantPathNode(16...23)(
            SelfNode(16...20)(),
            ConstantReadNode(22...23)(),
            (20...22)
          ),
          nil,
          nil
        ),
        LocalVariableWriteNode(25...28)((25...28), nil, nil, 0)],
       EQUAL(29...30)("="),
       LocalVariableReadNode(31...34)(0),
       nil,
       nil
     )]
  )
)
