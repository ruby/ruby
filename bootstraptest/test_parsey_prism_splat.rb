# A sole splatted jump argument remains an array, including empty results.
assert_equal '[[], [1], [1, 2]]', %q{
  RubyVM::InstructionSequence.compile_parsey('def parsey_splat(x); return *x; end; [parsey_splat(nil),parsey_splat(1),parsey_splat([1,2])]').eval.inspect
}

assert_equal '[[], [[1, 2]]]', %q{
  RubyVM::InstructionSequence.compile_parsey('a=[0].each { break *nil }; b=[0].map { next *[1,2] }; [a,b]').eval.inspect
}

assert_equal '[[1], [1, 2]]', %q{
  RubyVM::InstructionSequence.compile_parsey('def parsey_splat(x); return *x; end; a=[1]; b=parsey_splat(a); b << 2; [a,b]').eval.inspect
}

assert_equal '[[4, 5], [:to_a]]', %q{
  RubyVM::InstructionSequence.compile_parsey('events=[]; o=Object.new; o.define_singleton_method(:to_a) { events << :to_a; [4,5] }; def parsey_splat(x); return *x; end; [parsey_splat(o),events]').eval.inspect
}

assert_equal '[[1, 2], [3, 4], [[5, 6]]]', %q{
  RubyVM::InstructionSequence.compile_parsey('def a(*); return *; end; def b(*); [0].each { break * }; end; def c(*); [0].map { next * }; end; [a(1,2),b(3,4),c(5,6)]').eval.inspect
}
