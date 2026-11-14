# Keep the harness on Prism while exercising the remaining parse.y nodes.

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

# Rescue and ensure expressions retain parse.y's existing singleton validation.
assert_equal 'true', %q{
  ['begin "s"; rescue; Object.new; end', 'begin "s"; ensure; nil; end'].all? do |receiver|
    RubyVM::InstructionSequence.compile_parsey("def (#{receiver}).f; end")
  end
}

assert_equal '[true, true, true]', %q{
  RubyVM::InstructionSequence.compile_parsey('["literal".freeze.frozen?, (-"literal").frozen?, __FILE__.freeze.frozen?]').eval.inspect
}

assert_equal 'true', %q{
  ['$1 = nil', '$& += "x"', '$1, x = []'].all? do |source|
    begin
      RubyVM::InstructionSequence.compile_parsey(source)
      false
    rescue SyntaxError => error
      error.message.include?("Can't set variable $")
    end
  end
}

assert_equal 'true', %q{
  begin
    RubyVM::InstructionSequence.compile_parsey('def f; yield 1 do; end; end')
    false
  rescue SyntaxError => error
    error.message.include?('block given to yield')
  end
}

assert_equal 'true', %q{
  ['"s"', '1', '1.0', '1r', '1i', '/a/', ':a', '[]', '__FILE__', '__LINE__', '__ENCODING__', '"#{1}"'].all? do |literal|
    begin
      RubyVM::InstructionSequence.compile_parsey("def (#{literal}).f; end")
      false
    rescue SyntaxError => error
      error.message.include?("can't define singleton method for literals")
    end
  end
}
