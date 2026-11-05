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
  'def parsey_void; value = (case :value; when :value; return; else; return; end); end',
  'def parsey_void; value = (case; when true; return; else; return; end); end',
  'def parsey_void; value = (case :value; in :value; return; else; return; end); end',
  'def parsey_void; value = (:value => :value); end',
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
  [':value', 'def parsey_value; value = (case :value; when :early; return; else; :value; end); value; end; parsey_value'],
  ['nil', 'def parsey_value; value = (case :value; when :early; return; end); value; end; parsey_value'],
  [':value', 'def parsey_value; value = (case :value; in :early; return; else; :value; end); value; end; parsey_value'],
  ['true', 'def parsey_value; value = (:value in :value); value; end; parsey_value'],
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

# Error recovery must release nested pattern tables without popping a closed scope twice.
assert_equal 'true', <<~'RUBY'
  sources = [
    'case {}; in {a:',
    'case {}; in {first: 1, outer: {inner:',
    'case {}; in Hash(a: {b:',
    'case {}; in Hash[a:',
    'case {}; in Hash(a:',
    'case {}; in {}; (',
    'case 1; in first; case 2; in second;',
  ]
  3.times do
    sources.each do |source|
      begin
        RubyVM::InstructionSequence.compile_parsey(source)
        raise 'malformed pattern accepted'
      rescue SyntaxError
      end
    end
    GC.start
  end
  RubyVM::InstructionSequence.compile_parsey('case {a: {a: 1}}; in {a: {a: 0}}; false; in {a: {a: value}}; value; end').eval == 1
RUBY
