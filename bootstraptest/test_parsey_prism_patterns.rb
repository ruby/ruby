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
].each do |expected, source|
  assert_equal expected, "RubyVM::InstructionSequence.compile_parsey(#{source.dump}).eval.inspect"
end

