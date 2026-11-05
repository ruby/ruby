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

