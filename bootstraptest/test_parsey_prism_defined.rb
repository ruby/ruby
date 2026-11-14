# Keep the test driver independent of parse.y's defined? implementation.

assert_equal '["nil", "true", "false", "self", "expression", "local-variable", "assignment", nil]', %q{
  RubyVM::InstructionSequence.compile_parsey('x = 1; [defined?(nil), defined?(true), defined?(false), defined?(self), defined?(1), defined?(x), defined?(x = 2), defined?(parsey_undefined)]').eval.inspect
}

assert_equal '[nil, nil, nil, "expression", "method"]', %q{
  RubyVM::InstructionSequence.compile_parsey('[defined?([*parsey_undefined]), defined?({a: parsey_undefined}), defined?(puts(**parsey_undefined)), defined?({a: itself}), defined?(puts(a: itself))]').eval.inspect
}

assert_equal '["method", 2, nil, 2]', %q{
  RubyVM::InstructionSequence.compile_parsey('$parsey_calls = 0; def self.parsey_receiver; $parsey_calls += 1; self; end; result = defined?(parsey_receiver.parsey_receiver.parsey_receiver); first = $parsey_calls; missing = defined?(parsey_unknown.parsey_receiver); [result, first, missing, $parsey_calls]').eval.inspect
}

assert_equal '["constant", "constant", nil, nil]', %q{
  RubyVM::InstructionSequence.compile_parsey('[defined?(::Object), defined?(File::Constants), defined?(ParseyMissing::Child), defined?(@parsey_missing)]').eval.inspect
}

assert_equal '[nil, "global-variable", nil, nil, "expression", "nil"]', %q{
  RubyVM::InstructionSequence.compile_parsey('before = defined?($1); /(a)/ =~ "a"; [before, defined?($1), defined?($2), defined?((x;)), defined?((;x)), defined?(())]').eval.inspect
}

assert_equal '[nil, "expression", "expression", "method", "method"]', %q{
  RubyVM::InstructionSequence.compile_parsey('[defined?([*parsey_missing]), defined?([1, *parsey_missing]), defined?([*nil, parsey_missing]), defined?(puts(parsey_missing, &nil)), defined?(puts(*parsey_missing, &nil))]').eval.inspect
}

assert_equal '["method", "expression", nil]', %q{
  RubyVM::InstructionSequence.compile_parsey('def parsey_forward(...); defined?(puts(parsey_missing, ...)); end; [parsey_forward, defined? (parsey_missing;), defined?((parsey_missing;))]').eval.inspect
}

assert_equal '["expression", "expression", "method"]', %q{
  RubyVM::InstructionSequence.compile_parsey('[defined?([parsey_missing, *[]]), defined?([*[], parsey_missing]), defined?(puts(parsey_missing, *[]))]').eval.inspect
}

assert_equal '[["assignment", "assignment", "assignment", "assignment"], 0]', %q{
  RubyVM::InstructionSequence.compile_parsey('$parsey_effect = 0; x = 0; values = [defined?(x += ($parsey_effect += 1)), defined?(@x ||= ($parsey_effect += 1)), defined?($x &&= ($parsey_effect += 1)), defined?((x, y = ($parsey_effect += 1)))]; [values, $parsey_effect]').eval.inspect
}
