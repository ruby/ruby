#
# IMPORTANT: Always keep the first 7 lines (comments),
# even if this file is otherwise empty.
#
# This test file includes tests which point out known bugs.
# So all tests will cause failure.
#
assert_normal_exit("#{<<~"begin;"}\n#{<<~'end;#1'}", timeout: 5)
begin;
  str = "#{<<~"begin;"}\n#{<<~'end;'}"
  begin;
    class P
      def p; end
      def q; end
      E = ""
      N = "#{E}"
      attr_reader :i
      undef p
      undef q
      remove_const :E
      remove_const :N
    end
  end;
  iseq = RubyVM::InstructionSequence.compile(str)
  100.times {|i|
    bin = iseq.to_binary
    RubyVM::InstructionSequence.load_from_binary(bin).eval
  }
end;#1
