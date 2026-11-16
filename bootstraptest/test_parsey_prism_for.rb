# For loops use an internal block but keep their targets in the surrounding scope.

assert_equal '[[1, 2, 3], [1, 2, 3], 3, 9]', %q{
  RubyVM::InstructionSequence.compile_parsey('seen=[]; result=for x in [1,2,3]; seen << x; y=9; end; [seen,result,x,y]').eval.inspect
}

assert_equal '[4, nil, []]', %q{
  RubyVM::InstructionSequence.compile_parsey('x=4; result=for x in []; y=9; end; [x,y,result]').eval.inspect
}

assert_equal '[[nil, 1, [3, 4]], :result, [3, 4]]', %q{
  RubyVM::InstructionSequence.compile_parsey('o=Object.new; def o.each; yield; yield 1,2; yield [3,4]; :result; end; seen=[]; result=for x in o; seen << x; end; [seen,result,x]').eval.inspect
}

assert_equal '[[[1, [2], 3], [4, [], nil]], 4, [], nil]', %q{
  RubyVM::InstructionSequence.compile_parsey('seen=[]; for a,*b,c in [[1,2,3],[4]]; seen << [a,b,c]; end; [seen,a,b,c]').eval.inspect
}

assert_equal '[[1, 2, 3], [4, 5, 6]]', %q{
  RubyVM::InstructionSequence.compile_parsey('seen=[]; for (a,b),c in [[[1,2],3],[[4,5],6]]; seen << [a,b,c]; end; seen').eval.inspect
}

assert_equal '[7, 8, 9]', %q{
  RubyVM::InstructionSequence.compile_parsey('a=[]; for @x,$parsey_for,a[0] in [[7,8,9]]; end; [@x,$parsey_for,a[0]]').eval.inspect
}

assert_equal '[[1, 1, 2, 3], :done, 3]', %q{
  RubyVM::InstructionSequence.compile_parsey('seen=[]; again=true; result=for x in [1,2,3,4]; seen << x; if again; again=false; redo; end; next if x==2; break :done if x==3; end; [seen,result,x]').eval.inspect
}

assert_equal '[5, 2]', %q{
  RubyVM::InstructionSequence.compile_parsey('o=Object.new; def o.to_ary; [5,6]; end; seen=[]; for a,b in [o]; seen=[a,b]; end; [seen[0], (for x in [1,2]; end).size]').eval.inspect
}

assert_equal '[[], [1, 2]]', %q{
  RubyVM::InstructionSequence.compile_parsey('o=nil; seen=[]; result=for o&.x in [1,2]; end; [seen,result]').eval.inspect
}

assert_equal '[[1, [[:opt]]], [-1, [[:rest]]], [-1, [[:rest]]]]', %q{
  RubyVM::InstructionSequence.compile_parsey('o=Object.new; def o.each(&b); [b.arity,b.parameters]; end; [(for x in o; end), (for @x in o; end), (for x,y in o; end)]').eval.inspect
}
