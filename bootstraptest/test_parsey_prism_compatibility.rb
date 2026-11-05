assert_equal 'true', %q{
  warnings=[]
  Warning.define_singleton_method(:warn) { |message| warnings << message }
  $VERBOSE=true
  RubyVM::InstructionSequence.compile_parsey("loop do\nbreak\nfoo\nend", 'test')
  warnings == ["test:3: warning: statement not reached\n"]
}

assert_equal 'true', %q{
  warnings=[]
  Warning.define_singleton_method(:warn) { |message| warnings << message }
  $VERBOSE=true
  RubyVM::InstructionSequence.compile_parsey('{**{}, foo: :bar, **{foo: :foo}}')
  warnings.any? { |message| message.include?('key :foo is duplicated') }
}

assert_equal '[1, 0, 3]', %q{
  warnings=[]
  Warning.define_singleton_method(:warn) { |message| warnings << message }
  $VERBOSE=true
  ['{**{a:1,a:2}}', '{**{a:0}, **{a:1}}', '{a:0, **{a:1,a:2}}'].map do |source|
    warnings.clear
    RubyVM::InstructionSequence.compile_parsey(source)
    warnings.count { |message| message.include?('is duplicated') }
  end.inspect
}

