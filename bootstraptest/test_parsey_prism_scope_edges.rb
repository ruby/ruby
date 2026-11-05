assert_equal '[1]', %q{
  RubyVM::InstructionSequence.compile_parsey('[1].each { 1 => ^it }').eval.inspect
}

assert_equal '[:matched, :matched]', %q{
  RubyVM::InstructionSequence.compile_parsey(<<~'RUBY').eval.inspect
    [true, false].map do |value|
      value.instance_eval do
        case value
        when self then :matched
        else :missed
        end
      end
    end
  RUBY
}

