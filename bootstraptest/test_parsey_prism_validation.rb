# Migrated control-flow nodes must still be rejected in value-only positions.
[
  'def parsey_void; value = (return :value); end',
  'def parsey_void; value = (return; :unreachable); end',
  'def parsey_void; value = (begin :value; rescue; return; else; return; end); end',
  'def parsey_void; [begin return :value end]; end',
  'def parsey_void; value = (if true; return :first; else; return :last; end); end',
  'while true; value = (break); end',
  'while true; parsey_void(next); end',
  'def parsey_void; value = (begin return :value; ensure :ensured; end); end',
  'def parsey_void; value = (begin :value; ensure return :ensured; end); end',
  'def parsey_void; value = (begin return :value; rescue; return :fallback; end); end',
  'def parsey_void; value = ((return :value) || :fallback); end',
].each do |source|
  assert_equal 'SyntaxError', <<~RUBY
    begin
      RubyVM::InstructionSequence.compile_parsey(#{source.dump})
      :accepted
    rescue SyntaxError => error
      error.class.name
    end
  RUBY
end

[
  [':value', 'def parsey_value; value = (if false; return :early; else; :value; end); value; end; parsey_value'],
  ['nil', 'def parsey_value; value = (if false; return :early; end); value; end; parsey_value'],
  [':value', 'def parsey_value; value = (begin :value; rescue; return :early; end); value; end; parsey_value'],
  [':fallback', 'def parsey_value; value = (begin raise; rescue; :fallback; end); value; end; parsey_value'],
  [':value', 'def parsey_value; value = (begin :value; ensure :ensured; end); value; end; parsey_value'],
  ['false', 'def parsey_value; value = (false && (return :early)); value; end; parsey_value'],
].each do |expected, source|
  assert_equal expected, "RubyVM::InstructionSequence.compile_parsey(#{source.dump}).eval.inspect"
end

assert_equal 'false', <<~'RUBY'
  source = '$parsey_chain = true; ' + (['$parsey_chain'] * 2000 + ['false']).join(' && ')
  RubyVM::InstructionSequence.compile_parsey(source).eval.inspect
RUBY

assert_equal ':last', <<~'RUBY'
  source = '$parsey_chain = false; ' + (['$parsey_chain'] * 2000 + [':last']).join(' || ')
  RubyVM::InstructionSequence.compile_parsey(source).eval.inspect
RUBY
