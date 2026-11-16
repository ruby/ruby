# Exercise pre/post execution and command-line lowering through parse.y.

assert_equal '[:first, :second, :body]', %q{
  $parsey_events = []
  RubyVM::InstructionSequence.compile_parsey('$parsey_events << :body; BEGIN { $parsey_events << :first }; BEGIN { $parsey_events << :second }').eval
  $parsey_events.inspect
}

assert_equal '2', %q{
  RubyVM::InstructionSequence.compile_parsey('BEGIN { x = 2 }; x').eval
}

assert_equal "body\n2", %q{
  RubyVM::InstructionSequence.compile_parsey('x = 1; END { print "\n#{x}" }; x = 2; "body"').eval
}

assert_equal "body\nsecond\nfirst", %q{
  RubyVM::InstructionSequence.compile_parsey('END { print "\nfirst" }; END { print "\nsecond" }; "body"').eval
}

if BT.ruby
  ["-n -e 'print $_.upcase'", "-p -e '$_.upcase!'", "-lp -e '$_.upcase!'"].each do |options|
    command = "#{BT.ruby} --parser=parse.y #{options}"
    assert_equal "A\nB\n", %Q{
      IO.popen(#{command.dump}, 'r+') do |io|
        io.write("a\\nb\\n")
        io.close_write
        io.read
      end
    }
  end
  command = "#{BT.ruby} --parser=parse.y -aln -e 'p [$_, $F]'"
  assert_equal "[\"a b\", [\"a\", \"b\"]]\n", %Q{
    IO.popen(#{command.dump}, 'r+') do |io|
      io.write("a b\\n")
      io.close_write
      io.read
    end
  }
end
