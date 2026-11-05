assert_equal '[["a", "b c"], ["a", "b2"], [:a, :"b c"], [:a, :b2], []]', %q{
  RubyVM::InstructionSequence.compile_parsey('[%w[a b\ c], %W[a b#{1+1}], %i[a b\ c], %I[a b#{1+1}], %I[]]').eval.inspect
}

assert_equal '[:"12", :"34"]', %q{
  RubyVM::InstructionSequence.compile_parsey('$parsey_word = 12; @parsey_word = 34; %I[#$parsey_word #@parsey_word]').eval.inspect
}

assert_equal '["a", ["ab", "ac"]]', %q{
  RubyVM::InstructionSequence.compile_parsey('$parsey_word = "a"; words = %W[#$parsey_word #{$parsey_word}]; words[0] << "b"; words[1] << "c"; [$parsey_word, words]').eval.inspect
}

assert_equal '[false, false, true]', %q{
  RubyVM::InstructionSequence.compile_parsey('class ParseyUndef; def a; end; def b; end; def c; end; undef a, :"#{:b}"; end; [:a, :b, :c].map { |name| ParseyUndef.method_defined?(name) }').eval.inspect
}

assert_equal '[true, true, true]', %q{
  RubyVM::InstructionSequence.compile_parsey('["literal".freeze.frozen?, (-"literal").frozen?, __FILE__.freeze.frozen?]').eval.inspect
}

