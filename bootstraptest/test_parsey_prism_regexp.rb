# Regexp options must also select the encoding of an empty dynamic prefix.
assert_equal '["EUC-JP", "Windows-31J", "UTF-8", "US-ASCII"]', %q{
  RubyVM::InstructionSequence.compile_parsey('[/#{}/e, /#{}/s, /#{}/u, /#{}/n].map { |r| r.encoding.name }').eval.inspect
}

assert_equal '["ASCII-8BIT", true]', %q{
  source = %q{s = '\xc2\xa1'; r = /#{s}/; [r.encoding == Encoding::ASCII_8BIT ? 'ASCII-8BIT' : r.encoding.name, r.fixed_encoding?]}.force_encoding(Encoding::US_ASCII)
  RubyVM::InstructionSequence.compile_parsey(source).eval.inspect
}

assert_equal '["US-ASCII", "UTF-8"]', %q{
  ascii = RubyVM::InstructionSequence.compile_parsey(%q{/#{%q"\x80"}/.encoding.name}.force_encoding(Encoding::US_ASCII)).eval
  utf8 = RubyVM::InstructionSequence.compile_parsey(%q{/#{"a"}/e.encoding.name}).eval
  [ascii, utf8].inspect
}
