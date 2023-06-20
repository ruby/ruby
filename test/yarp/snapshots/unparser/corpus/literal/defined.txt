ProgramNode(0...56)(
  [:a, :b],
  StatementsNode(0...56)(
    [DefinedNode(0...14)(
       (8...9),
       InstanceVariableReadNode(9...13)(),
       (13...14),
       (0...8)
     ),
     DefinedNode(15...28)(
       (23...24),
       ConstantReadNode(24...27)(),
       (27...28),
       (15...23)
     ),
     DefinedNode(29...56)(
       (37...38),
       ParenthesesNode(38...55)(
         StatementsNode(40...54)(
           [MultiWriteNode(40...54)(
              [LocalVariableWriteNode(40...41)(:a, 0, nil, (40...41), nil),
               LocalVariableWriteNode(43...44)(:b, 0, nil, (43...44), nil)],
              (46...47),
              ArrayNode(48...54)(
                [IntegerNode(49...50)(), IntegerNode(52...53)()],
                (48...49),
                (53...54)
              ),
              (39...40),
              (44...45)
            )]
         ),
         (38...39),
         (54...55)
       ),
       (55...56),
       (29...37)
     )]
  )
)
