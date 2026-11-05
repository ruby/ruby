# Keep the harness on Prism while testing each migrated construct with parse.y.

# https://yui-knk.hatenablog.com/entry/2025/12/12/212854
assert_equal 'nil', 'RubyVM::InstructionSequence.compile_parsey("").eval.inspect'
assert_equal 'nil', 'RubyVM::InstructionSequence.compile_parsey("nil").eval.inspect'
assert_equal 'true', 'RubyVM::InstructionSequence.compile_parsey("true").eval.inspect'
assert_equal 'false', 'RubyVM::InstructionSequence.compile_parsey("false").eval.inspect'
assert_equal 'true', 'RubyVM::InstructionSequence.compile_parsey("self").eval.equal?(self)'
assert_equal 'true', 'RubyVM::InstructionSequence.compile_parsey("nil; false; self; true").eval.inspect'
assert_equal 'parser-node-source.rb', 'RubyVM::InstructionSequence.compile_parsey("__FILE__", "parser-node-source.rb").eval'
assert_equal '41', 'RubyVM::InstructionSequence.compile_parsey("\n__LINE__", "test.rb", "test.rb", 40).eval'
assert_equal 'US-ASCII', 'RubyVM::InstructionSequence.compile_parsey("# coding: US-ASCII\n__ENCODING__").eval.name'

assert_equal 'false', 'RubyVM::InstructionSequence.compile_parsey("if self; false; else; true; end").eval.inspect'
assert_equal 'true', 'RubyVM::InstructionSequence.compile_parsey("if false; false; elsif true; true; else; false; end").eval.inspect'
assert_equal 'false', 'RubyVM::InstructionSequence.compile_parsey("if false; true; elsif nil; true; else; false; end").eval.inspect'
assert_equal 'nil', 'RubyVM::InstructionSequence.compile_parsey("if false; true; end").eval.inspect'
assert_equal 'nil', 'RubyVM::InstructionSequence.compile_parsey("if true; end").eval.inspect'
assert_equal 'false', 'RubyVM::InstructionSequence.compile_parsey("if true; end; false").eval.inspect'
assert_equal 'true', 'RubyVM::InstructionSequence.compile_parsey("unless false; true; else; false; end").eval.inspect'
assert_equal 'false', 'RubyVM::InstructionSequence.compile_parsey("unless true; true; else; false; end").eval.inspect'
assert_equal 'nil', 'RubyVM::InstructionSequence.compile_parsey("(true if false)").eval.inspect'
assert_equal 'false', 'RubyVM::InstructionSequence.compile_parsey("(false unless nil)").eval.inspect'

# https://yui-knk.hatenablog.com/entry/2025/12/13/132433
assert_equal 'nil', 'RubyVM::InstructionSequence.compile_parsey("$parsey_uninitialized").eval.inspect'
assert_equal 'true', 'RubyVM::InstructionSequence.compile_parsey("$parsey_value = true; $parsey_value").eval.inspect'
assert_equal 'nil', 'RubyVM::InstructionSequence.compile_parsey("@parsey_uninitialized").eval.inspect'
assert_equal 'false', 'RubyVM::InstructionSequence.compile_parsey("@parsey_value = false; @parsey_value").eval.inspect'
assert_equal 'false', 'RubyVM::InstructionSequence.compile_parsey("value = true; other = false; value = other; value").eval.inspect'
assert_equal 'nil', 'RubyVM::InstructionSequence.compile_parsey("value = value; value").eval.inspect'
assert_equal 'class variable access from toplevel', %q{
  begin
    RubyVM::InstructionSequence.compile_parsey("@@parsey_value").eval
  rescue RuntimeError => error
    error.message
  end
}
assert_equal 'class variable access from toplevel', %q{
  begin
    RubyVM::InstructionSequence.compile_parsey("@@parsey_value = true").eval
  rescue RuntimeError => error
    error.message
  end
}

# https://yui-knk.hatenablog.com/entry/2025/12/15/123905
assert_equal 'false', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(first, last); last; end").eval
  parsey_method(true, false)
}
assert_equal 'true', %q{
  RubyVM::InstructionSequence.compile_parsey("def self.parsey_method(value); value; end").eval
  self.parsey_method(true)
}
assert_equal 'false', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(value) = value").eval
  parsey_method(false)
}
assert_equal 'true', %q{
  RubyVM::InstructionSequence.compile_parsey("def self.parsey_method(value) = value").eval
  self.parsey_method(true)
}
assert_equal '[false, true]', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(first, optional = first); optional; end").eval
  [parsey_method(false), parsey_method(false, true)].inspect
}
assert_equal '[1, 2]', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(first, *rest, last); rest; end").eval
  parsey_method(true, 1, 2, false).inspect
}
assert_equal 'false', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(optional = true, *rest, last); last; end").eval
  parsey_method(false)
}
assert_equal 'ArgumentError', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(first, last); last; end").eval
  begin
    parsey_method(true)
  rescue ArgumentError => error
    error.class.name
  end
}

# https://yui-knk.hatenablog.com/entry/2025/12/17/162208
assert_equal 'ok', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(value: :ok); value; end").eval
  parsey_method
}
assert_equal '1', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(value: __LINE__); value; end").eval
  parsey_method
}
assert_equal 'US-ASCII', %q{
  RubyVM::InstructionSequence.compile_parsey("# coding: US-ASCII\ndef parsey_method(value: __ENCODING__); value; end").eval
  parsey_method.name
}
assert_equal '[true, false, :rejected]', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(value: true, &nil); value; end").eval
  [parsey_method, parsey_method(value: false), begin
    parsey_method {}
  rescue ArgumentError
    :rejected
  end].inspect
}
assert_equal '[true, false]', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(required:, optional: true); optional; end").eval
  [parsey_method(required: false), parsey_method(required: false, optional: false)].inspect
}
assert_equal '[false, true]', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(first:, second: first); second; end").eval
  [parsey_method(first: false), parsey_method(first: false, second: true)].inspect
}
assert_equal 'true', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(required:, **rest); rest; end").eval
  parsey_method(required: true, extra: false) == {extra: false}
}
assert_equal '[true, :rejected]', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(**nil); true; end").eval
  [parsey_method, begin
    parsey_method(extra: true)
  rescue ArgumentError
    :rejected
  end].inspect
}
assert_equal '[true, false]', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(&block); block; end").eval
  [parsey_method.nil?, parsey_method { false }.call].inspect
}
assert_equal '[false, true]', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(optional: nil, required:, **rest, &block); required; end").eval
  [parsey_method(required: false), parsey_method(optional: false, required: true, extra: nil) {}].inspect
}
assert_equal 'ArgumentError', %q{
  RubyVM::InstructionSequence.compile_parsey("def parsey_method(required:); required; end").eval
  begin
    parsey_method
  rescue ArgumentError => error
    error.class.name
  end
}
