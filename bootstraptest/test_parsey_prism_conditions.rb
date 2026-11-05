
assert_equal '[]', %q{
  warnings = []
  Warning.define_singleton_method(:warn) { |message| warnings << message }
  $VERBOSE = true
  RubyVM::InstructionSequence.compile_parsey('def used; i=0; 1.times { i+=1 }; end; def logical; a=1; a ||= 2; b=1; b &&= 2; end')
  warnings.inspect
}
