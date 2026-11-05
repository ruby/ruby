assert_equal '[1]', %q{
  RubyVM::InstructionSequence.compile_parsey('[1].each { 1 => ^it }').eval.inspect
}

