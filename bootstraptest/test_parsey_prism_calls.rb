# Keep the harness on Prism while testing each migrated construct with parse.y.

# https://yui-knk.hatenablog.com/entry/2025/12/18/201310
assert_equal 'true', %q{
  def parsey_call; true; end
  RubyVM::InstructionSequence.compile_parsey("parsey_call").eval
}
assert_equal 'false', %q{
  def parsey_call; false; end
  RubyVM::InstructionSequence.compile_parsey("self.parsey_call()").eval
}
assert_equal 'NameError', %q{
  begin
    RubyVM::InstructionSequence.compile_parsey("parsey_missing").eval
  rescue NameError => error
    error.class.name
  end
}
assert_equal 'NoMethodError', %q{
  begin
    RubyVM::InstructionSequence.compile_parsey("parsey_missing()").eval
  rescue NameError => error
    error.class.name
  end
}
assert_equal 'NoMethodError', %q{
  begin
    RubyVM::InstructionSequence.compile_parsey("parsey_missing?").eval
  rescue NameError => error
    error.class.name
  end
}
assert_equal 'nil', 'RubyVM::InstructionSequence.compile_parsey("nil&.parsey_missing").eval.inspect'
assert_equal 'false', 'RubyVM::InstructionSequence.compile_parsey("false&.nil?").eval.inspect'
assert_equal '-4', %q{
  $parsey_number = 6
  $parsey_other = 2
  RubyVM::InstructionSequence.compile_parsey("-$parsey_number + $parsey_other").eval
}
assert_equal '[nil, [:receiver]]', %q{
  $parsey_events = []
  def parsey_receiver; $parsey_events << :receiver; nil; end
  def parsey_argument; $parsey_events << :argument; end
  result = RubyVM::InstructionSequence.compile_parsey("parsey_receiver&.call(parsey_argument)").eval
  [result, $parsey_events].inspect
}

# https://yui-knk.hatenablog.com/entry/2025/12/22/105349
assert_equal 'true', %q{
  $parsey_hash = {positional: true}
  def parsey_call(*args, **keywords); [args, keywords]; end
  RubyVM::InstructionSequence.compile_parsey("parsey_call($parsey_hash, keyword: false)").eval ==
    [[{positional: true}], {keyword: false}]
}
assert_equal 'true', %q{
  begin
    RubyVM::InstructionSequence.compile_parsey("parsey_call(&$parsey_block) {}")
  rescue SyntaxError => error
    error.message.include?("both block") && error.message.include?("actual block given")
  end
}

# https://yui-knk.hatenablog.com/entry/2025/12/23/115553
assert_equal '[true, false, nil]', %q{
  def parsey_call(*args); args; end
  RubyVM::InstructionSequence.compile_parsey("parsey_call(true, false, nil)").eval.inspect
}
assert_equal '[[nil, true, false, :added], [true, false]]', %q{
  $parsey_args = [true, false].freeze
  def parsey_call(*args); args << :added; end
  result = RubyVM::InstructionSequence.compile_parsey("parsey_call(nil, *$parsey_args)").eval
  [result, $parsey_args].inspect
}
assert_equal '[[nil, true, false, nil, false, true], [true], [true]]', %q{
  $parsey_first = [true].freeze
  $parsey_last = [true].freeze
  def parsey_call(*args); args; end
  result = RubyVM::InstructionSequence.compile_parsey("parsey_call(nil, *$parsey_first, false, nil, false, *$parsey_last)").eval
  [result, $parsey_first, $parsey_last].inspect
}
assert_equal '[[:first, :last], [:first, :changed]]', %q{
  $parsey_args = [:first]
  def parsey_later; $parsey_args << :changed; :last; end
  def parsey_call(*args); args; end
  result = RubyVM::InstructionSequence.compile_parsey("parsey_call(*$parsey_args, parsey_later)").eval
  [result, $parsey_args].inspect
}
assert_equal '[true, false]', %q{
  $parsey_array_like = Object.new
  def $parsey_array_like.to_a; [true, false]; end
  def parsey_call(*args); args; end
  RubyVM::InstructionSequence.compile_parsey("parsey_call(*$parsey_array_like)").eval.inspect
}
assert_equal '[true, false]', %q{
  def parsey_call(*args); args; end
  RubyVM::InstructionSequence.compile_parsey("parsey_call(true, *nil, false)").eval.inspect
}

# https://yui-knk.hatenablog.com/entry/2025/12/26/001646
assert_equal '[nil, true, false]', %q{
  def parsey_call(positional, first:, second:); [positional, first, second]; end
  RubyVM::InstructionSequence.compile_parsey("parsey_call(nil, first: true, second: false)").eval.inspect
}
assert_equal 'true', %q{
  $parsey_events = []
  def parsey_key; $parsey_events << :key; "dynamic"; end
  def parsey_value; $parsey_events << :value; false; end
  def parsey_call(**keywords); keywords; end
  result = RubyVM::InstructionSequence.compile_parsey("parsey_call(first: true, parsey_key => parsey_value, last: nil)").eval
  result == {first: true, "dynamic" => false, last: nil} && $parsey_events == [:key, :value]
}
assert_equal 'true', %q{
  $parsey_keywords = {first: true, middle: nil}.freeze
  def parsey_call(**keywords); keywords[:added] = true; keywords; end
  result = RubyVM::InstructionSequence.compile_parsey("parsey_call(first: false, **$parsey_keywords, last: true)").eval
  result == {first: true, middle: nil, last: true, added: true} &&
    $parsey_keywords == {first: true, middle: nil}
}
assert_equal 'true', %q{
  $parsey_keywords = {first: true}.freeze
  def parsey_call(**keywords); keywords.clear; keywords; end
  result = RubyVM::InstructionSequence.compile_parsey("parsey_call(**$parsey_keywords)").eval
  result.empty? && $parsey_keywords == {first: true}
}
assert_equal 'true', %q{
  $parsey_args = [true].freeze
  $parsey_keywords = {required: false, extra: nil}.freeze
  def parsey_call(*args, required:, **keywords)
    keywords.clear
    [args, required]
  end
  result = RubyVM::InstructionSequence.compile_parsey("parsey_call(*$parsey_args, nil, **$parsey_keywords)").eval
  result == [[true, nil], false] && $parsey_args == [true] &&
    $parsey_keywords == {required: false, extra: nil}
}
assert_equal 'true', %q{
  def parsey_call(*args, **keywords); args.empty? && keywords.empty?; end
  RubyVM::InstructionSequence.compile_parsey("parsey_call(**nil)").eval
}
assert_equal 'true', %q{
  $parsey_args = [:first]
  def parsey_keyword; $parsey_args << :changed; false; end
  def parsey_call(*args, **keywords); [args, keywords]; end
  result = RubyVM::InstructionSequence.compile_parsey("parsey_call(*$parsey_args, key: parsey_keyword)").eval
  result == [[:first], {key: false}] && $parsey_args == [:first, :changed]
}
assert_equal 'true', %q{
  $parsey_args = [:first]
  def parsey_keywords; $parsey_args << :changed; {key: false}; end
  def parsey_call(*args, **keywords); [args, keywords]; end
  result = RubyVM::InstructionSequence.compile_parsey("parsey_call(*$parsey_args, **parsey_keywords)").eval
  result == [[:first], {key: false}] && $parsey_args == [:first, :changed]
}

# https://yui-knk.hatenablog.com/entry/2025/12/27/115614
assert_equal '[true, false]', %q{
  $parsey_block = proc { |first, second| [first, second] }
  def parsey_call(positional, keyword:, &block); block.call(positional, keyword); end
  RubyVM::InstructionSequence.compile_parsey("parsey_call(true, keyword: false, &$parsey_block)").eval.inspect
}
assert_equal 'false', %q{
  def parsey_call; block_given?; end
  RubyVM::InstructionSequence.compile_parsey("parsey_call(&nil)").eval
}
assert_equal 'false', %q{
  def parsey_call; yield; end
  RubyVM::InstructionSequence.compile_parsey("parsey_call { false }").eval
}
assert_equal 'true', %q{
  def parsey_call; yield; end
  RubyVM::InstructionSequence.compile_parsey("parsey_call do true end").eval
}
assert_equal '[[:first], [:first, :changed]]', %q{
  $parsey_args = [:first]
  def parsey_block; $parsey_args << :changed; proc {}; end
  def parsey_call(*args, &block); args; end
  result = RubyVM::InstructionSequence.compile_parsey("parsey_call(*$parsey_args, &parsey_block)").eval
  [result, $parsey_args].inspect
}
assert_equal 'true', %q{
  $parsey_keywords = {key: true}
  def parsey_block; $parsey_keywords[:key] = false; proc {}; end
  def parsey_call(**keywords, &block); keywords; end
  result = RubyVM::InstructionSequence.compile_parsey("parsey_call(**$parsey_keywords, &parsey_block)").eval
  result == {key: true} && $parsey_keywords == {key: false}
}

# https://yui-knk.hatenablog.com/entry/2025/12/28/234328
assert_equal 'false', %q{
  def parsey_call; yield [true, false]; end
  RubyVM::InstructionSequence.compile_parsey("parsey_call { |first, last| last }").eval
}
assert_equal '[false]', %q{
  def parsey_call; yield true, false, nil; end
  RubyVM::InstructionSequence.compile_parsey("parsey_call { |first, *rest, last| rest }").eval.inspect
}
assert_equal 'true', %q{
  def parsey_call; yield; end
  RubyVM::InstructionSequence.compile_parsey("parsey_call { |value = true| value }").eval
}
assert_equal 'false', %q{
  def parsey_call; yield required: false, extra: true; end
  RubyVM::InstructionSequence.compile_parsey("parsey_call { |required:, **extra| required }").eval
}
assert_equal 'false', %q{
  RubyVM::InstructionSequence.compile_parsey("value = false; true.tap { |; value| value = true }; value").eval
}
assert_equal '[true, false]', %q{
  result = RubyVM::InstructionSequence.compile_parsey("outer = false; true.tap { |middle| false.tap { |inner| outer = middle; $parsey_seen = inner } }; outer").eval
  [result, $parsey_seen].inspect
}
assert_equal 'NameError', %q{
  begin
    RubyVM::InstructionSequence.compile_parsey("true.tap { inner = false }; inner").eval
  rescue NameError => error
    error.class.name
  end
}
assert_equal 'false', %q{
  def parsey_call; yield true, false; end
  RubyVM::InstructionSequence.compile_parsey("parsey_call { _2 }").eval
}
assert_equal 'false', %q{
  def parsey_call; yield [true, false]; end
  RubyVM::InstructionSequence.compile_parsey("parsey_call { _2 }").eval
}
assert_equal '[true, false]', %q{
  def parsey_call; yield [true, false]; end
  RubyVM::InstructionSequence.compile_parsey("parsey_call { _1 }").eval.inspect
}
assert_equal '[true, false]', %q{
  def parsey_call; yield [true, false]; end
  RubyVM::InstructionSequence.compile_parsey("parsey_call { it }").eval.inspect
}
assert_equal '[false, true, false]', %q{
  $parsey_values = []
  RubyVM::InstructionSequence.compile_parsey("false.tap { $parsey_values.push(it); true.tap { $parsey_values.push(it) }; $parsey_values.push(it) }").eval
  $parsey_values.inspect
}
assert_equal 'true', 'RubyVM::InstructionSequence.compile_parsey("true.then { value = false; it }").eval'
assert_equal 'true', %q{
  begin
    RubyVM::InstructionSequence.compile_parsey("true.tap { |value| it }")
  rescue SyntaxError => error
    error.message.include?("ordinary parameter")
  end
}
