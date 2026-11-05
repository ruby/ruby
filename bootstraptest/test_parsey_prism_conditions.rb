# Run these through parse.y even when the bootstrap driver uses Prism.

assert_equal '[[2], [2, 3, 4], [1, 5]]', %q{
  RubyVM::InstructionSequence.compile_parsey('[(1..5).select { |n| true if (n == 2)..n.even? }, (1..5).select { |n| true if (n == 2)...n.even? }, (1..5).select { |n| true unless (n == 2)..(n == 4) }]').eval.inspect
}

assert_equal '[[2, 3, 4], [1, 5]]', %q{
  $VERBOSE = nil
  RubyVM::InstructionSequence.compile_parsey('[(1..5).select { |n| $. = n; true if 2..4 }, (1..5).select { |n| !(n == 2..n == 4) }]').eval.inspect
}

assert_equal '[true, "a", [1, 2], 2]', %q{
  $VERBOSE = nil
  RubyVM::InstructionSequence.compile_parsey('$_ = "a"; result = if /a/ then true end; matched = $~[0]; count = 0; items = [1, 2].select { if /#{count += 1; "a"}/o then true end }; [result, matched, items, count]').eval.inspect
}

assert_equal '1', %q{
  RubyVM::InstructionSequence.compile_parsey('count = 0; 2.times { /#{count += 1}/o }; count').eval
}

assert_equal '[false, true, true]', %q{
  $VERBOSE = nil
  RubyVM::InstructionSequence.compile_parsey('$_ = "a"; [!/a/, (true && /a/) ? true : false, (false || /a/) ? true : false]').eval.inspect
}

assert_equal 'true', %q{
  warnings = []
  Warning.define_singleton_method(:warn) { |message| warnings << message }
  $VERBOSE = true
  RubyVM::InstructionSequence.compile_parsey('1; if (a = [1, {x: 2}]); end; if "literal"; end')
  warnings.any? { |message| message.include?('possibly useless use of a literal in void context') } &&
    warnings.any? { |message| message.include?("found '= literal' in conditional, should be ==") } &&
    warnings.any? { |message| message.include?('string literal in condition') }
}

assert_equal '[]', %q{
  warnings = []
  Warning.define_singleton_method(:warn) { |message| warnings << message }
  $VERBOSE = true
  RubyVM::InstructionSequence.compile_parsey('def used; i=0; 1.times { i+=1 }; end; def logical; a=1; a ||= 2; b=1; b &&= 2; end')
  warnings.inspect
}
