assert_equal '[[1, 2, 3], [2, 2, 3], [4, 5]]', %q{
  RubyVM::InstructionSequence.compile_parsey(<<~'RUBY').eval.inspect
    splat = [2, 3]
    receiver = Object.new
    def receiver.[](value, &block); block.call(value); end
    [Array[1, *splat, &nil], Array[2, *splat, **nil, &nil],
     receiver[4, &->(value) { [value, value + 1] }]]
  RUBY
}

assert_equal '[true, true, true]', %q{
  RubyVM::InstructionSequence.compile_parsey(<<~'RUBY').eval.inspect
    results = []
    begin
      a = 1
      Ractor.shareable_proc { a }
      a = 2
      results << false
    rescue Ractor::IsolationError
      results << true
    end
    begin
      cond = false
      b = 1
      b = 2 if cond
      Ractor.shareable_proc { b }
      results << false
    rescue Ractor::IsolationError
      results << true
    end
    1.times do |i|
      begin
        i = 2
        Ractor.shareable_proc { i }
        results << false
      rescue Ractor::IsolationError
        results << true
      end
    end
    results
  RUBY
}

assert_equal 'true', %q{
  ['yield(&:+)', 'def f; yield &nil; end'].all? do |source|
    begin
      RubyVM::InstructionSequence.compile_parsey(source)
      false
    rescue SyntaxError => error
      error.message.include?('block argument should not be given')
    end
  end
}
