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

assert_equal '[1, 2]', %q{
  RubyVM::InstructionSequence.compile_parsey(<<~'RUBY').eval.inspect
    objects = []
    $parsey_singleton_number = 0
    2.times do
      objects << object = Object.new
      class << object
        NUMBER = ($parsey_singleton_number += 1)
        def number; NUMBER; end
      end
    end
    objects.map(&:number)
  RUBY
}
