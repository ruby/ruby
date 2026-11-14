# Keep the harness on Prism while compiling the specimens with parse.y.
[
  # https://yui-knk.hatenablog.com/entry/2026/02/15/133356
  ['[3, [3], 1]', <<~'RUBY'],
    a = [1]
    calls = 0
    value = (a[(calls += 1) - 1] += 2)
    [value, a, calls]
  RUBY
  ['[2, 3, [3], 0]', <<~'RUBY'],
    a = [nil]
    calls = 0
    first = (a[0] ||= 2)
    a[0] ||= (calls += 1)
    last = (a[0] &&= 3)
    [first, last, a, calls]
  RUBY
  ['[3, 3]', <<~'RUBY'],
    obj = Object.new
    def obj.value; @value; end
    def obj.value=(value); @value = value; false; end
    obj.value = 1
    result = (obj.value += 2)
    [result, obj.value]
  RUBY
  ['[2, 3, 3]', <<~'RUBY'],
    obj = Struct.new(:value).new
    first = (obj.value ||= 2)
    last = (obj.value &&= 3)
    [first, last, obj.value]
  RUBY
  ['[nil, nil, nil, 0]', <<~'RUBY'],
    obj = nil
    calls = 0
    a = (obj&.value += (calls += 1))
    b = (obj&.value ||= (calls += 1))
    c = (obj&.value &&= (calls += 1))
    [a, b, c, calls]
  RUBY

  # https://yui-knk.hatenablog.com/entry/2026/02/17/095217
  ['[3, 4, 5, 0]', <<~'RUBY'],
    value = nil
    calls = 0
    a = (value ||= 3)
    value ||= (calls += 1)
    b = (value &&= 4)
    c = (value += 1)
    [a, b, c, calls]
  RUBY
  ['3', 'value = 1; 1.times { value += 2 }; value'],
  ['[2, 4, 6]', <<~'RUBY'],
    @value ||= 1
    @value += 1
    @value &&= 2
    $parsey_op_value ||= 3
    $parsey_op_value += 1
    class ParseyOpClass
      @@value ||= 5
      @@value += 1
      def self.value; @@value; end
    end
    [@value, $parsey_op_value, ParseyOpClass.value]
  RUBY
  ['[:ok, false, 1]', <<~'RUBY'],
    $parsey_cond = false
    result = if $parsey_cond; :bad; else; :ok; end
    calls = 0
    if ($parsey_cond = false); calls += 100; end
    if ($parsey_cond ||= false); calls += 100; end
    if ($parsey_cond &&= true); calls += 100; end
    if -> { false }; calls += 1; end
    [result, $parsey_cond, calls]
  RUBY

  # https://yui-knk.hatenablog.com/entry/2026/02/21/214036
  ['[3, 4, 5]', <<~'RUBY'],
    A ||= 1
    A += 2
    module ParseyOpConstants
      B ||= 2
    end
    ParseyOpConstants::B += 2
    ::C ||= 5
    [A, ParseyOpConstants::B, ::C]
  RUBY
  ['[false, 3, 0]', <<~'RUBY'],
    A = false
    B = 2
    calls = 0
    A &&= (calls += 1)
    B ||= (calls += 1)
    B &&= 3
    [A, B, calls]
  RUBY
  ['3', <<~'RUBY'],
    # shareable_constant_value: literal
    A = 1
    A += 2
    A
  RUBY
  ['[[:a, :b], true]', <<~'RUBY'],
    # shareable_constant_value: experimental_copy
    A = [:a]
    A += [:b]
    [A, A.frozen?]
  RUBY

  # https://yui-knk.hatenablog.com/entry/2026/02/22/135412
  [':second', 'case 2; when 0, 1; :first; when 2, 3; :second; else; :other; end'],
  [':splat', 'values = [1, 2]; case 2; when *values; :splat; else; :other; end'],
  [':second', 'case; when false, nil; :first; when true; :second; else; :other; end'],
  [':splat', 'case; when *[false, true]; :splat; else; :other; end'],
  ['nil', 'case 0; when 1; :unreachable; end'],
  ['[:match, [:first, :second]]', <<~'RUBY'],
    trace = []
    result = case 2
    when (trace << :first; 1), (trace << :second; 2), (trace << :third; 3)
      :match
    else
      :other
    end
    [result, trace]
  RUBY

  # https://yui-knk.hatenablog.com/entry/2026/02/25/211533
  [':integer', 'case 1; in String; :string; in ::Integer; :integer; else; :other; end'],
  [':other', 'case :sym; in String; :string; in Integer; :integer; else; :other; end'],
  ['"NoMatchingPatternError"', <<~'RUBY'],
    begin
      case :sym
      in String; :unreachable
      end
    rescue NoMatchingPatternError => error
      error.class.name
    end
  RUBY

  # https://yui-knk.hatenablog.com/entry/2026/03/01/114534
  [':range', 'case 2; in 3; :number; in 1..2; :range; end'],
  [':pin', 'value = :sym; case :sym; in ^value; :pin; else; :other; end'],
  [':expression', 'case 3; in ^(1 + 2); :expression; else; :other; end'],
  [':string', 'case "str"; in "str"; :string; else; :other; end'],

  # https://yui-knk.hatenablog.com/entry/2026/03/02/155905
  ['[2, 2]', 'result = case 2; in value; value; end; [result, value]'],
  ['[2, 2]', 'result = case 2; in value if value == 2; value; else; nil; end; [result, value]'],
  ['2', 'case 2; in value unless value == 1; value; else; nil; end'],
  ['[:fallback, 2]', 'result = case 2; in value if false; :bad; else; :fallback; end; [result, value]'],
  ['true', <<~'RUBY'],
    begin
      case 1
      in value if false; :bad
      end
    rescue NoMatchingPatternError => error
      error.message.include?("guard clause does not return true")
    end
  RUBY

  # https://yui-knk.hatenablog.com/entry/2026/05/05/165740
  ['[1, [2, 3], 4]', 'case [1, 2, 3, 4]; in [first, *rest, last]; [first, rest, last]; end'],
  [':prefix', 'case [1, 2, 3]; in [1, 2,]; :prefix; else; :other; end'],
  [':other', 'case [1, 2, 3]; in [1, 2]; :exact; else; :other; end'],
  ['[1, 2]', 'case [1, [2]]; in Array[first, [last]]; [first, last]; end'],
  ['[2, 1]', <<~'RUBY'],
    obj = Object.new
    def obj.deconstruct; $parsey_deconstruct_calls += 1; [2]; end
    $parsey_deconstruct_calls = 0
    result = case obj
    in [1]; :bad
    in [value]; value
    end
    [result, $parsey_deconstruct_calls]
  RUBY
  ['"TypeError"', <<~'RUBY'],
    obj = Object.new
    def obj.deconstruct; :invalid; end
    begin
      case obj
      in []; :bad
      else; :other
      end
    rescue TypeError => error
      error.class.name
    end
  RUBY

  # https://yui-knk.hatenablog.com/entry/2026/05/06/091215
  ['[1, {b: 2}, {a: 1, b: 2}]', <<~'RUBY'],
    original = {a: 1, b: 2}
    case original
    in {a:, **rest}; [a, rest, original]
    end
  RUBY
  [':match', 'case {a: 1, b: 2}; in {a: 1, **}; :match; else; :other; end'],
  [':other', 'case {a: 1, b: 2}; in {a: 1, **nil}; :match; else; :other; end'],
  ['1', 'case {a: 1}; in {"a": value}; value; end'],
  ['[1, [:a]]', <<~'RUBY'],
    obj = Object.new
    def obj.deconstruct_keys(keys); $parsey_keys = keys; {a: 1, b: 2}; end
    result = case obj
    in {a:}; a
    end
    [result, $parsey_keys]
  RUBY
  ['[{b: 2}, nil]', <<~'RUBY'],
    obj = Object.new
    def obj.deconstruct_keys(keys); $parsey_keys = keys; {a: 1, b: 2}; end
    result = case obj
    in {a:, **rest}; rest
    end
    [result, $parsey_keys]
  RUBY
  ['["NoMatchingPatternKeyError", :a, {}]', <<~'RUBY'],
    begin
      case {}
      in {a:}; a
      end
    rescue NoMatchingPatternKeyError => error
      [error.class.name, error.key, error.matchee]
    end
  RUBY

  # https://yui-knk.hatenablog.com/entry/2026/05/07/225306
  ['[[0], [3]]', 'case [0, 1, 2, 3]; in [*before, 1, 2, *after]; [before, after]; end'],
  [':found', 'case [0, 1, 2, 3]; in [*, 1, 2, *]; :found; else; :other; end'],
  [':other', 'case [0, 1]; in [*, 1, 2, *]; :found; else; :other; end'],

  # https://yui-knk.hatenablog.com/entry/2026/05/08/221718
  [':match', 'case :b; in :a | :b; :match; else; :other; end'],
  [':other', 'case :c; in :a | :b; :match; else; :other; end'],
  ['2', 'case [2]; in [1] | [_value]; _value; end'],

  # https://yui-knk.hatenablog.com/entry/2026/05/09/124324
  ['[2, "str"]', 'case [2, "str"]; in [Integer => number, String => string]; [number, string]; end'],
  ['[[1, 2], 1]', 'case [1, 2]; in [first, *] => whole; [whole, first]; end'],

  # https://yui-knk.hatenablog.com/entry/2026/05/09/194026
  ['true', '[1, 2] in [1, 2]'],
  ['false', '[1, 2] in [1, 3]'],
  ['[1, 2]', '[1, 2] => [a, b]; [a, b]'],
  ['nil', '[1, 2] => [1, 2]'],
  ['"NoMatchingPatternError"', <<~'RUBY'],
    begin
      [1, 2] => [1, 3]
    rescue NoMatchingPatternError => error
      error.class.name
    end
  RUBY
  ['["NoMatchingPatternKeyError", :a]', <<~'RUBY'],
    begin
      {} => {a:}
    rescue NoMatchingPatternKeyError => error
      [error.class.name, error.key]
    end
  RUBY
].each do |expected, source|
  assert_equal expected, "RubyVM::InstructionSequence.compile_parsey(#{source.dump}).eval.inspect"
end

assert_equal 'SyntaxError', %q{
  begin
    RubyVM::InstructionSequence.compile_parsey('case [1]; in [value] | [2]; end')
  rescue SyntaxError => error
    error.class.name
  end
}


[
  'case [1]; in [value] | [1]; end',
  'case {a: 1}; in {a: value} | {}; end',
  'case [1]; in [*value] | []; end',
  'case [1]; in [*, value, *] | []; end',
  'case [1]; in ([Integer] => value) | []; end',
].each do |source|
  assert_equal 'SyntaxError', %Q{
    begin
      RubyVM::InstructionSequence.compile_parsey(#{"if false; #{source}; end".dump})
      :accepted
    rescue SyntaxError => error
      error.class.name
    end
  }
end
assert_equal ':ok', 'RubyVM::InstructionSequence.compile_parsey("case [1]; in [_value] | [1]; :ok; end").eval.inspect'

# Rest-only hash patterns have no key vector and accept nonempty hashes.
assert_equal '[{a: 1}, {}, true]', %q{
  RubyVM::InstructionSequence.compile_parsey('a = case {a:1}; in **rest; rest; end; b = case {}; in **rest; rest; end; c = case {a:1}; in **; true; else; false; end; [a,b,c]').eval.inspect
}

assert_equal '[false, true, false, true]', %q{
  RubyVM::InstructionSequence.compile_parsey('[case {a:1}; in **nil; true; else; false; end, case {}; in **nil; true; else; false; end, case {a:1}; in {}; true; else; false; end, case {}; in {}; true; else; false; end]').eval.inspect
}

assert_equal '[[], nil, [:a], nil]', %q{
  RubyVM::InstructionSequence.compile_parsey('calls=[]; o=Object.new; o.define_singleton_method(:deconstruct_keys) { |keys| calls << keys; {a:1} }; case o; in **; end; case o; in **rest; end; case o; in a:; end; case o; in {}; else; end; calls').eval.inspect
}
