assert_equal '[10, 20, 30, [10, 20, 30]]', %q{
  b = RubyVM::InstructionSequence.compile_parsey('existing = 1; binding').eval
  b.local_variable_set(:existing, 10)
  b.local_variable_set(:fresh, 20)
  b.local_variable_set(:another, 30)
  [b.local_variable_get(:existing), b.local_variable_get(:fresh),
   b.local_variable_get(:another), b.eval('[existing, fresh, another]')].inspect
}
