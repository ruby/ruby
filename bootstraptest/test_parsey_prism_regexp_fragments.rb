assert_equal '[SyntaxError, SyntaxError, SyntaxError]', %q{
  $VERBOSE = nil
  sources = [%q{/\u1234#{%q"\x80"}/}, %q{/\u1234#{"\x80"}/}, %q!/#{"! + 92.chr * 2 + %q!"}y/!]
  sources.map do |source|
    begin
      RubyVM::InstructionSequence.compile_parsey(source.force_encoding(Encoding::US_ASCII))
      :accepted
    rescue SyntaxError, Encoding::CompatibilityError => error
      error.class
    end
  end.inspect
}

assert_equal 'Encoding::CompatibilityError', %q{
  source = %q!/#{"\u1234"}#{"!.b + "\x82\xa0".b + %q!"}/!.b
  begin
    RubyVM::InstructionSequence.compile_parsey(source.force_encoding(Encoding::Windows_31J))
    :accepted
  rescue Encoding::CompatibilityError => error
    error.class
  end
}

assert_equal '["UTF-8", "EUC-JP", "EUC-JP", "UTF-8", "UTF-8", "EUC-JP"]', %q{
  RubyVM::InstructionSequence.compile_parsey('[/#{"a"}/e, /#{"a"}#{"b"}/e, /#{("a")}/e, /#{begin "a" end}/e, /#{"a";}/e, /#{;"a"}/e].map { |r| r.encoding.name }').eval.inspect
}
