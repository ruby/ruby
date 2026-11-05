# Behavior and diagnostics shared with the legacy parse.y implementation.
assert_equal '[44, 55]', %q{
  RubyVM::InstructionSequence.compile_parsey('class ParseySuperBase; def value(x); block_given? ? yield : x; end; end; class ParseySuperChild < ParseySuperBase; def value(x); [super(x,&nil),super]; end; end; ParseySuperChild.new.value(44) {55}').eval.inspect
}

assert_equal 'true', %q{
  ['def f(...); f(...) {}; end', 'def f(...); super(...) {}; end', 'def f(...); super(...) do end; end'].all? do |source|
    begin
      RubyVM::InstructionSequence.compile_parsey(source)
      false
    rescue SyntaxError => error
      error.message.include?('both block arg and actual block given')
    end
  end
}

assert_equal 'true', %q{
  begin
    RubyVM::InstructionSequence.compile_parsey('def b(k:, **) ->(**) {c(k: 1, **)} end')
    false
  rescue SyntaxError => error
    error.message.include?('anonymous keyword rest parameter is also used within block')
  end
}

assert_equal '3', %q{
  RubyVM::InstructionSequence.compile_parsey("def capture(*args, &block); block.source_location.last; end\ncapture(1,\n2) do\nend").eval
}

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

assert_equal '{k: 1, x: 2}', %q{
  RubyVM::InstructionSequence.compile_parsey('def parsey_kwargs(k:, **); parsey_values(k: k, **); end; def parsey_values(**kw); kw; end; parsey_kwargs(k: 1, x: 2)').eval.inspect
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

assert_equal 'true', %q{
  ['def f(*rest, ...); end', 'def f(*, ...); end'].all? do |source|
    begin
      RubyVM::InstructionSequence.compile_parsey(source)
      false
    rescue SyntaxError => error
      error.message.include?('... after rest argument')
    end
  end
}
