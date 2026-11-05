# Keep the harness on Prism while testing each migrated construct with parse.y.

# https://yui-knk.hatenablog.com/entry/2025/12/29/225740
assert_equal '[true, true]', %q{
  $parsey_receiver = Object.new
  def $parsey_receiver.value=(value); $parsey_written = value; false; end
  result = RubyVM::InstructionSequence.compile_parsey("$parsey_receiver.value = true").eval
  [result, $parsey_written].inspect
}
assert_equal '[nil, false]', %q{
  $parsey_evaluated = false
  result = RubyVM::InstructionSequence.compile_parsey("nil&.value = ($parsey_evaluated = true)").eval
  [result, $parsey_evaluated].inspect
}
assert_equal '[true, [:first, :last, true]]', %q{
  $parsey_receiver = Object.new
  $parsey_indices = [:first, :last]
  def $parsey_receiver.[]=(*args); $parsey_written = args; false; end
  result = RubyVM::InstructionSequence.compile_parsey("$parsey_receiver[*$parsey_indices] = true").eval
  [result, $parsey_written].inspect
}
assert_equal '[true, [true]]', %q{
  $parsey_receiver = Object.new
  def $parsey_receiver.[]=(*args); $parsey_written = args; false; end
  result = RubyVM::InstructionSequence.compile_parsey("$parsey_receiver[] = true").eval
  [result, $parsey_written].inspect
}
assert_equal 'true', %q{
  begin
    RubyVM::InstructionSequence.compile_parsey("$parsey_receiver[key: true] = false")
  rescue SyntaxError => error
    error.message.include?("keyword arg given in index assignment")
  end
}
assert_equal 'true', %q{
  begin
    RubyVM::InstructionSequence.compile_parsey("$parsey_receiver[&nil] = false")
  rescue SyntaxError => error
    error.message.include?("block arg given in index assignment")
  end
}

# https://yui-knk.hatenablog.com/entry/2026/01/01/234613
assert_equal '[true, [false, nil], true, nil]', %q{
  $parsey_values = [true, false, nil, true]
  RubyVM::InstructionSequence.compile_parsey("first, *rest, last = $parsey_values; missing, = nil; [first, rest, last, missing]").eval.inspect
}
assert_equal '[true, false, nil]', %q{
  $parsey_values = [[true, false], nil]
  RubyVM::InstructionSequence.compile_parsey("(first, *, last), tail = $parsey_values; [first, last, tail]").eval.inspect
}

# https://yui-knk.hatenablog.com/entry/2026/01/03/113957
assert_equal '[true, false]', 'RubyVM::InstructionSequence.compile_parsey("first, last = true, false; [first, last]").eval.inspect'
assert_equal '[true, false, nil]', 'RubyVM::InstructionSequence.compile_parsey("first, middle, last = true, false; [first, middle, last]").eval.inspect'
assert_equal '[[true, false], [:extra]]', %q{
  $parsey_events = []
  def parsey_extra; $parsey_events.push(:extra); nil; end
  result = RubyVM::InstructionSequence.compile_parsey("first, last = true, false, parsey_extra; [first, last]").eval
  [result, $parsey_events].inspect
}
assert_equal '[true, false]', %q{
  $parsey_values = [true, false]
  RubyVM::InstructionSequence.compile_parsey("first, last = *$parsey_values; [first, last]").eval.inspect
}
assert_equal 'true', %q{
  $parsey_values = [true, false]
  RubyVM::InstructionSequence.compile_parsey("first, last = $parsey_values").eval.equal?($parsey_values)
}
assert_equal '[true, false, nil]', %q{
  $parsey_values = [true, false, nil]
  RubyVM::InstructionSequence.compile_parsey("local, @parsey_ivar, $parsey_global = $parsey_values; [local, @parsey_ivar, $parsey_global]").eval.inspect
}
# https://yui-knk.hatenablog.com/entry/2026/01/04/163105
assert_equal 'true', %q{
  $parsey_events = []
  $parsey_receiver = Object.new
  $parsey_values = [[true, false], nil]
  def parsey_receiver; $parsey_events << :receiver; $parsey_receiver; end
  def parsey_index; $parsey_events << :index; :key; end
  def parsey_values; $parsey_events << :rhs; $parsey_values; end
  def $parsey_receiver.[]=(key, value); $parsey_events << [key, value]; :ignored; end
  def $parsey_receiver.value=(value); $parsey_events << [:value, value]; :ignored; end
  result = RubyVM::InstructionSequence.compile_parsey("(parsey_receiver[parsey_index], local), parsey_receiver.value = parsey_values").eval
  result.equal?($parsey_values) &&
    $parsey_events == [:receiver, :index, :receiver, :rhs, [:key, true], [:value, nil]]
}

# https://yui-knk.hatenablog.com/entry/2026/01/05/195618
assert_equal '[true, [false], nil, :tail, false]', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_method((first, *middle, last), *rest, (tail, other), key:); [first, middle, last, tail, key]; end").eval
  parsey_method([true, false, nil], [:tail], key: false).inspect
}
assert_equal '[:optional, :keyword, :destructure]', %q{
  $parsey_events = []
  $parsey_value = Object.new
  def $parsey_value.to_ary; $parsey_events << :destructure; [true, false]; end
  def parsey_default(value); $parsey_events << value; end
  RubyVM::InstructionSequence.compile_parsey("def parsey_method((first, last), optional = parsey_default(:optional), key: parsey_default(:keyword)); first; end").eval
  parsey_method($parsey_value)
  $parsey_events.inspect
}

# https://yui-knk.hatenablog.com/entry/2026/01/08/000300
assert_equal '[true, false]', %q{
  ParseyNamespace = Module.new
  RubyVM::InstructionSequence.compile_parsey("ParseyValue = true; ::ParseyNamespace::Value = false; [::ParseyValue, ParseyNamespace::Value]").eval.inspect
}
assert_equal '[true, true]', %q{
  ParseyNamespace = Module.new
  ParseyNamespace::Value = true
  def parsey_namespace; ParseyNamespace; end
  RubyVM::InstructionSequence.compile_parsey("[parsey_namespace::Value, ::ParseyNamespace::Value]", "test.rb", "test.rb", 1, inline_const_cache: false).eval.inspect
}

# https://yui-knk.hatenablog.com/entry/2026/01/10/105419
assert_equal '[true, false, nil]', %q{
  ParseyNamespace = Module.new
  $parsey_values = [true, false, nil]
  def parsey_namespace; ParseyNamespace; end
  RubyVM::InstructionSequence.compile_parsey("ParseyFirst, ::ParseyLast, parsey_namespace::Value = $parsey_values; [ParseyFirst, ParseyLast, ParseyNamespace::Value]").eval.inspect
}
assert_equal '[true, true]', %q{
  value = RubyVM::InstructionSequence.compile_parsey("# shareable_constant_value: literal\nParseyValue = [true, [false]]").eval
  [value.frozen?, value.last.frozen?].inspect
}
assert_equal '[true, true, false, false]', %q{
  $parsey_value = ["value"]
  value = RubyVM::InstructionSequence.compile_parsey("# shareable_constant_value: experimental_copy\nParseyValue = $parsey_value").eval
  [value.frozen?, value.first.frozen?, value.equal?($parsey_value), $parsey_value.frozen?].inspect
}
assert_equal '[true, true, true]', %q{
  $parsey_value = ["value"]
  value = RubyVM::InstructionSequence.compile_parsey("# shareable_constant_value: experimental_everything\nParseyValue = $parsey_value").eval
  [value.equal?($parsey_value), value.frozen?, value.first.frozen?].inspect
}

# https://yui-knk.hatenablog.com/entry/2026/01/10/155309
assert_equal 'true', %q{
  RubyVM::InstructionSequence.compile_parsey("module ParseyNamespace; class Parent; Value = true; end; class Child < Parent; def value; Value; end; end; end").eval
  ParseyNamespace::Child.new.value
}
assert_equal '[false, true]', %q{
  RubyVM::InstructionSequence.compile_parsey("class ParseyClass; @@value = false; @@value, Other = [false, true]; def self.value; @@value; end; end").eval
  [ParseyClass.value, ParseyClass::Other].inspect
}
assert_equal 'false', %q{
  $parsey_receiver = Object.new
  RubyVM::InstructionSequence.compile_parsey("class << $parsey_receiver; def value; false; end; end").eval
  $parsey_receiver.value
}

# https://yui-knk.hatenablog.com/entry/2026/01/14/094050
assert_equal '[:else, [:body, :else, :ensure]]', %q{
  $parsey_events = []
  result = RubyVM::InstructionSequence.compile_parsey("begin; $parsey_events.push(:body); rescue; :rescued; else; $parsey_events.push(:else); :else; ensure; $parsey_events.push(:ensure); end").eval
  [result, $parsey_events].inspect
}
assert_equal '[true, [:ensure]]', %q{
  $parsey_events = []
  $parsey_errors = [ArgumentError]
  result = RubyVM::InstructionSequence.compile_parsey("begin; raise ArgumentError; rescue TypeError; false; rescue *$parsey_errors => error; error.is_a?(ArgumentError); ensure; $parsey_events.push(:ensure); end").eval
  [result, $parsey_events].inspect
}
# https://yui-knk.hatenablog.com/entry/2026/01/15/113728
assert_equal 'false', 'RubyVM::InstructionSequence.compile_parsey("raise(ArgumentError) rescue false").eval'
assert_equal '[ArgumentError, [:ensure]]', %q{
  $parsey_events = []
  begin
    RubyVM::InstructionSequence.compile_parsey("begin; raise ArgumentError; rescue TypeError; false; ensure; $parsey_events.push(:ensure); end").eval
  rescue ArgumentError => error
    [error.class, $parsey_events].inspect
  end
}
assert_equal 'true', %q{
  $parsey_receiver = Object.new
  def $parsey_receiver.error=(error); $parsey_error = error; end
  RubyVM::InstructionSequence.compile_parsey("begin; raise ArgumentError; rescue => $parsey_receiver.error; true; end").eval &&
    $parsey_error.is_a?(ArgumentError)
}
assert_equal 'true', %q{
  $parsey_receiver = {}
  result = RubyVM::InstructionSequence.compile_parsey("begin; raise ArgumentError; rescue => $parsey_receiver[:key]; true; end").eval
  result && $parsey_receiver.keys == [:key] && $parsey_receiver[:key].is_a?(ArgumentError)
}
assert_equal 'rescued', %q{
  RubyVM::InstructionSequence.compile_parsey("begin; raise ArgumentError; rescue => nil&.error; :rescued; end").eval
}
assert_equal 'true', %q{
  $parsey_error = Class.new(Exception)
  begin
    RubyVM::InstructionSequence.compile_parsey("raise($parsey_error) rescue :rescued").eval
  rescue Exception => error
    error.class.equal?($parsey_error)
  end
}

# https://yui-knk.hatenablog.com/entry/2026/01/16/144853
assert_equal '[:while, :until]', %q{
  $parsey_events = []
  RubyVM::InstructionSequence.compile_parsey("active = true; while active; $parsey_events.push(:while); active = false; end; until active; $parsey_events.push(:until); active = true; end").eval
  $parsey_events.inspect
}
assert_equal '[:post]', %q{
  $parsey_events = []
  RubyVM::InstructionSequence.compile_parsey("$parsey_events.push(:never) while false; begin; $parsey_events.push(:post); end while false").eval
  $parsey_events.inspect
}
assert_equal '[:attempt, :attempt]', %q{
  $parsey_events = []
  RubyVM::InstructionSequence.compile_parsey("again = true; begin; $parsey_events.push(:attempt); if again; again = false; raise; end; rescue; retry; end").eval
  $parsey_events.inspect
}

# https://yui-knk.hatenablog.com/entry/2026/01/25/114319
assert_equal '[false, [:ensure]]', %q{
  $parsey_events = []
  result = RubyVM::InstructionSequence.compile_parsey("while true; begin; break false; rescue; true; ensure; $parsey_events.push(:ensure); end; end").eval
  [result, $parsey_events].inspect
}
assert_equal '[false, true]', %q{
  $parsey_values = [true, false]
  RubyVM::InstructionSequence.compile_parsey("$parsey_values.map { |value| next false if value; true }").eval.inspect
}
assert_equal '[true, true]', %q{
  $parsey_events = []
  RubyVM::InstructionSequence.compile_parsey("again = true; true.tap { |value| $parsey_events.push(value); if again; again = false; redo; end }").eval
  $parsey_events.inspect
}

# https://yui-knk.hatenablog.com/entry/2026/01/25/225639
assert_equal '[true, false]', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(*args, **keywords); yield(*args, **keywords); end").eval
  parsey_method(true, key: false) { |value, key:| [value, key] }.inspect
}
assert_equal 'true', %q{
  class ParseyParent
    def value(*args, **keywords, &block); [args, keywords, block.call]; end
  end
  RubyVM::InstructionSequence.compile_parsey("class ParseyChild < ParseyParent; def value(*args, **keywords, &block); super; end; def explicit; super(true, key: false) { nil }; end; end").eval
  class ParseyParent
    alias explicit value
  end
  ParseyChild.new.value(false, key: true) { :block } == [[false], {key: true}, :block] &&
    ParseyChild.new.explicit == [[true], {key: false}, nil]
}
assert_equal '[false, true]', %q{
  $parsey_ensured = false
  RubyVM::InstructionSequence.compile_parsey("def parsey_method; true.tap { return false }; ensure; $parsey_ensured = true; end").eval
  [parsey_method, $parsey_ensured].inspect
}

# https://yui-knk.hatenablog.com/entry/2026/01/27/233543
assert_equal '[false, true]', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_original; false; end; alias parsey_copy parsey_original; def parsey_original; true; end").eval
  [parsey_copy, parsey_original].inspect
}
assert_equal 'false', %q{
  RubyVM::InstructionSequence.compile_parsey("$parsey_original = true; alias $parsey_copy $parsey_original; $parsey_copy = false; $parsey_original").eval
}
assert_equal 'true', %q{
  $parsey_regexp = /(a)(b)?/
  $parsey_string = "xabz"
  RubyVM::InstructionSequence.compile_parsey(%q{$parsey_regexp =~ $parsey_string; [$&, $`, $', $+, $1, $2]}).eval ==
    ["ab", "x", "z", "b", "a", "b"]
}

# https://yui-knk.hatenablog.com/entry/2026/01/29/102858
assert_equal 'true', %q{
  RubyVM::InstructionSequence.compile_parsey(%q{[?a, "b\nc", 'd\ne']}).eval == ["a", "b\nc", 'd\ne']
}
assert_equal 'left:true:false:right', %q{
  $parsey_value = false
  RubyVM::InstructionSequence.compile_parsey(%q{@value = true; "left:#@value:#$parsey_value:#{"right"}"}).eval
}
assert_equal 'ok', %q{
  $parsey_condition = false
  RubyVM::InstructionSequence.compile_parsey(%q{"#{if $parsey_condition; "bad"; else; "ok"; end}"}).eval
}

# https://yui-knk.hatenablog.com/entry/2026/01/30/000821
assert_equal 'lefttrue:right', %q{
  RubyVM::InstructionSequence.compile_parsey(%q{%Q(left#{true}) ":" 'right'}).eval
}
assert_equal 'true', %q{
  source = "value = :middle\n<<~TEXT\n  first\n    #{'#{value}'}\n\n  last\nTEXT\n"
  RubyVM::InstructionSequence.compile_parsey(source).eval == "first\n  middle\n\nlast\n"
}

# https://yui-knk.hatenablog.com/entry/2026/01/31/123124
assert_equal '["plain", "value:true"]', %q{
  def `(command); command; end
  RubyVM::InstructionSequence.compile_parsey(%q{[`plain`, `value:#{true}`]}).eval.inspect
}
assert_equal 'true', %q{
  def parsey_call(**keywords); keywords; end
  RubyVM::InstructionSequence.compile_parsey(%q{value = :middle; parsey_call("left_#{value}": :"right_#{value}")}).eval ==
    {left_middle: :right_middle}
}

# https://yui-knk.hatenablog.com/entry/2026/02/04/105814
assert_equal 'true', %q{
  regexp = RubyVM::InstructionSequence.compile_parsey(%q{/ a . b /imx}).eval
  regexp.match?("A\nB") && regexp.options == Regexp::IGNORECASE | Regexp::MULTILINE | Regexp::EXTENDED
}
assert_equal 'true', %q{
  $parsey_fragment = "b"
  regexp = RubyVM::InstructionSequence.compile_parsey(%q{/a#{$parsey_fragment}/u}).eval
  regexp.source == "ab" && regexp.encoding == Encoding::UTF_8
}
assert_equal '[true, 1]', %q{
  $parsey_count = 0
  def parsey_fragment; $parsey_count += 1; "a"; end
  RubyVM::InstructionSequence.compile_parsey(%q{def parsey_regexp; /#{parsey_fragment}/o; end}).eval
  first = parsey_regexp
  [parsey_regexp.equal?(first), $parsey_count].inspect
}

# https://yui-knk.hatenablog.com/entry/2026/02/07/115136
assert_equal 'true', %q{
  RubyVM::InstructionSequence.compile_parsey(%q{/(?<first>a)(?<last>b)/ =~ "ab"; matched = [first, last]; /(?<first>a)(?<last>b)/ =~ "z"; [matched, first, last]}).eval ==
    [["a", "b"], nil, nil]
}
assert_equal 'nil', 'RubyVM::InstructionSequence.compile_parsey(%q{/(?<value>a)/ =~ "z"; value}).eval.inspect'
assert_equal '[:value, :strict]', %q{
  function = RubyVM::InstructionSequence.compile_parsey("->(value) { return value }").eval
  [function.call(:value), begin
    function.call
  rescue ArgumentError
    :strict
  end].inspect
}

# https://yui-knk.hatenablog.com/entry/2026/02/08/121236
assert_equal 'true', %q{
  $parsey_keywords = {first: false}.freeze
  RubyVM::InstructionSequence.compile_parsey("last = true; {first: true, **$parsey_keywords, last:}").eval == {first: false, last: true} &&
    $parsey_keywords == {first: false}
}
assert_equal '[:key, :value]', %q{
  $parsey_events = []
  def parsey_mark(value); $parsey_events << value; value; end
  RubyVM::InstructionSequence.compile_parsey("{parsey_mark(:key) => parsey_mark(:value)}; nil").eval
  $parsey_events.inspect
}

# https://yui-knk.hatenablog.com/entry/2026/02/09/104635
assert_equal 'true', %q{
  $parsey_values = [true, false].freeze
  result = RubyVM::InstructionSequence.compile_parsey("[*$parsey_values, nil, *$parsey_values, key: true]").eval
  result == [true, false, nil, true, false, {key: true}] && $parsey_values == [true, false]
}
assert_equal '[true, false]', %q{
  $parsey_events = []
  def parsey_mark(value); $parsey_events << value; end
  RubyVM::InstructionSequence.compile_parsey("[parsey_mark(true), parsey_mark(false)]; nil").eval
  $parsey_events.inspect
}

# https://yui-knk.hatenablog.com/entry/2026/02/10/231442
assert_equal 'true', %q{
  RubyVM::InstructionSequence.compile_parsey("[0xff, 0b101, 0o17, 1_000, -2.5, 1.25r, 2ri, 123456789012345678901234567890]").eval ==
    [255, 5, 15, 1000, -2.5, Rational(5, 4), Complex(0, 2), 123456789012345678901234567890]
}
assert_equal 'true', %q{
  RubyVM::InstructionSequence.compile_parsey("[1..3, 1...3, ..3, 1..]").eval == [(1..3), (1...3), (..3), (1..)]
}
assert_equal 'true', %q{
  RubyVM::InstructionSequence.compile_parsey(%q{[{1 => :a, 2 => :b}, {a: 1, a: 2}, {"": 1, "": 2}, {"key" => 1, "key" => 2}, {1 => :a, 1 => :b}, {__FILE__ => :source, __LINE__ => :line}]}, "parsey-literals.rb").eval ==
    [{1 => :a, 2 => :b}, {a: 2}, {:"" => 2}, {"key" => 2}, {1 => :b}, {"parsey-literals.rb" => :source, 1 => :line}]
}

# https://yui-knk.hatenablog.com/entry/2026/02/11/215300
assert_equal 'true', %q{
  def parsey_target(*args, **keywords, &block); [args, keywords, block.call]; end
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(*, **, &); parsey_target(*, **, &); end").eval
  parsey_method(true, key: false) { nil } == [[true], {key: false}, nil]
}
assert_equal 'true', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(*, **); [[false, *, true], {before: true, **}, [**]]; end").eval
  parsey_method(nil, key: false) == [[false, nil, true], {before: true, key: false}, [{key: false}]]
}
assert_equal 'true', %q{
  def parsey_target(*args, **keywords, &block); [args, keywords, block.call]; end
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(prefix, ...); parsey_target(prefix, ...); end").eval
  parsey_method(true, nil, key: false) { :block } == [[true, nil], {key: false}, :block]
}

assert_equal '[:coerced]', %q{
  $parsey_events = []
  $parsey_values = Object.new
  def $parsey_values.to_a; $parsey_events << :coerced; []; end
  RubyVM::InstructionSequence.compile_parsey("[*$parsey_values]; nil").eval
  $parsey_events.inspect
}
assert_equal 'TypeError', %q{
  $parsey_values = Object.new
  def $parsey_values.to_a; false; end
  begin
    RubyVM::InstructionSequence.compile_parsey("[*$parsey_values]; nil").eval
  rescue TypeError => error
    error.class.name
  end
}
