assert_equal '[true, true, true, false]', %q{
  sources = ['"a" "b"', "<<~STR\n  a\nb\nSTR\n", "<<~STR\n  a\n  b\nSTR\n", "<<~STR\n  a\n  b\nc\nSTR\n"]
  sources.map do |source|
    RubyVM::InstructionSequence.compile_parsey(source, frozen_string_literal: true).eval.frozen?
  end.inspect
}

assert_equal '[:STR, :STR, :STR, :DSTR]', %q{
  sources = ['"a" "b"', "<<~STR\n  a\nb\nSTR\n", "<<~STR\n  a\n  b\nSTR\n", "<<~STR\n  a\n  b\nc\nSTR\n"]
  sources.map { |source| RubyVM::AbstractSyntaxTree.parse(source).children.last.type }.inspect
}

assert_equal '[3, 3, 14]', %q{
  ['"a" "b"', '"a" "b" "c"', '"a" "#{1}" "b"'].map do |source|
    RubyVM::AbstractSyntaxTree.parse(source).children.last.last_column
  end.inspect
}

assert_equal '["  b\nc\n", 3, 0, 3, 4]', %q{
  node = RubyVM::AbstractSyntaxTree.parse("<<~S\n  1\n  b\nc\nS\n").children.last.children[1]
  [node.children.first, node.first_lineno, node.first_column, node.last_lineno, node.last_column].inspect
}

assert_equal '["  a\nb\n", 1]', %q{
  $VERBOSE = false
  Warning[:deprecated] = true
  warnings = []
  Warning.define_singleton_method(:warn) { |message, **| warnings << message }
  value = RubyVM::InstructionSequence.compile_parsey("<<~STR\n  a\nb\nSTR\n").eval
  value << ''
  [value, warnings.size].inspect
}
