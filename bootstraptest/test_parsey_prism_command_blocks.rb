# A do block belongs to a command nested inside a jump's single argument.
assert_equal '[2, [3], 4]', %q{
  RubyVM::InstructionSequence.compile_parsey('def command_map(x); yield x; end; def command_return; return command_map 1 do |x| x+1 end; end; a=command_return; b=[0].map { next command_map 1 do |x| x+2 end }; c=loop { break command_map 1 do |x| x+3 end }; [a,b,c]').eval.inspect
}

assert_equal 'true', %q{
  begin
    RubyVM::InstructionSequence.compile_parsey('def command_return; return f 1, &nil do end; end')
    false
  rescue SyntaxError => error
    error.message.include?('both block arg and actual block given')
  end
}
