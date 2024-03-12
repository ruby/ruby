# frozen_string_literal: false
require 'test/unit'
EnvUtil.suppress_warning {require 'continuation'}

class TestBeginEndBlock < Test::Unit::TestCase
  DIR = File.dirname(File.expand_path(__FILE__))

  def test_beginendblock
    target = File.join(DIR, 'beginmainend.rb')
    assert_in_out_err([target], '', %w(b1 b2-1 b2 main b3-1 b3 b4 e1 e1-1 e4 e4-2 e4-1 e4-1-1 e3 e2))

    assert_in_out_err(["-n", "-eBEGIN{p :begin}", "-eEND{p :end}"], '', %w(:begin))
    assert_in_out_err(["-p", "-eBEGIN{p :begin}", "-eEND{p :end}"], '', %w(:begin))
    assert_in_out_err(["-n", "-eBEGIN{p :begin}", "-eEND{p :end}"], "foo\nbar\n", %w(:begin :end))
    assert_in_out_err(["-p", "-eBEGIN{p :begin}", "-eEND{p :end}"], "foo\nbar\n", %w(:begin foo bar :end))
  end

  def test_endblock_variable
    assert_in_out_err(["-n", "-ea = :ok", "-eEND{p a}"], "foo\n", %w(:ok))
    assert_in_out_err(["-p", "-ea = :ok", "-eEND{p a}"], "foo\n", %w(foo :ok))
  end

  def test_begininmethod
    assert_raise_with_message(SyntaxError, /BEGIN is permitted only at toplevel/) do
      eval("def foo; BEGIN {}; end")
    end

    assert_raise_with_message(SyntaxError, /BEGIN is permitted only at toplevel/) do
      eval('eval("def foo; BEGIN {}; end")')
    end
  end

  def test_begininclass
    assert_raise_with_message(SyntaxError, /BEGIN is permitted only at toplevel/) do
      eval("class TestBeginEndBlock; BEGIN {}; end")
    end
  end

  def test_endblockwarn
    assert_in_out_err([], "#{<<~"begin;"}#{<<~'end;'}", [], ['-:2: warning: END in method; use at_exit'])
    begin;
      def end1
        END {}
      end
    end;
  end

  def test_endblockwarn_in_eval
    assert_in_out_err([], "#{<<~"begin;"}\n#{<<~'end;'}", [], ['test.rb:1: warning: END in method; use at_exit'])
    begin;
      eval <<-EOE, nil, "test.rb", 0
        def end2
          END {}
        end
      EOE
    end;
  end

  def test_raise_in_at_exit
    args = ['-e', 'at_exit{raise %[SomethingBad]}',
            '-e', 'raise %[SomethingElse]']
    expected = [:*, /SomethingBad/, :*, /SomethingElse/, :*]
    status = assert_in_out_err(args, '', [], expected, "[ruby-core:9675]")
    assert_not_predicate(status, :success?)
  end

  def test_exitcode_in_at_exit
    bug8501 = '[ruby-core:55365] [Bug #8501]'
    args = ['-e', 'o = Object.new; def o.inspect; raise "[Bug #8501]"; end',
            '-e', 'at_exit{o.nope}']
    status = assert_in_out_err(args, '', [], /undefined method 'nope'/, bug8501)
    assert_not_predicate(status, :success?, bug8501)
  end

  def test_propagate_exit_code
    ruby = EnvUtil.rubybin
    assert_equal false, system(ruby, '-e', 'at_exit{exit 2}')
    assert_equal 2, $?.exitstatus
    assert_nil $?.termsig
  end

  def test_propagate_signaled
    status = assert_in_out_err([], "#{<<~"begin;"}\n#{<<~'end;'}", [], /Interrupt$/)
    begin;
      trap(:INT, "DEFAULT")
      at_exit{Process.kill(:INT, $$)}
    end;
    Process.kill(0, 0) rescue return # check if signal works
    assert_nil status.exitstatus
    assert_equal Signal.list["INT"], status.termsig
  end

  def test_endblock_raise
    assert_in_out_err([], "#{<<~"begin;"}\n#{<<~'end;'}", %w(e6 e4 e2), [:*, /e5/, :*, /e3/, :*, /e1/, :*])
    begin;
      END {raise "e1"}; END {puts "e2"}
      END {raise "e3"}; END {puts "e4"}
      END {raise "e5"}; END {puts "e6"}
    end;
  end

  def test_nested_at_exit
    expected = [ "outer3",
                 "outer2_begin",
                 "outer2_end",
                 "inner2",
                 "outer1_begin",
                 "outer1_end",
                 "inner1",
                 "outer0" ]

    assert_in_out_err([], "#{<<~"begin;"}\n#{<<~'end;'}", expected, [], "[ruby-core:35237]")
    begin;
      at_exit { puts :outer0 }
      at_exit { puts :outer1_begin; at_exit { puts :inner1 }; puts :outer1_end }
      at_exit { puts :outer2_begin; at_exit { puts :inner2 }; puts :outer2_end }
      at_exit { puts :outer3 }
    end;
  end

  def test_rescue_at_exit
    bug5218 = '[ruby-core:43173][Bug #5218]'
    cmd = [
      "raise 'X' rescue nil",
      "nil",
      "exit(42)",
    ]
    %w[at_exit END].each do |ex|
      out, err, status = EnvUtil.invoke_ruby(cmd.map {|s|["-e", "#{ex} {#{s}}"]}.flatten, "", true, true)
      assert_equal(["", "", 42], [out, err, status.exitstatus], "#{bug5218}: #{ex}")
    end
  end

  def test_callcc_at_exit
    omit 'requires callcc support' unless respond_to?(:callcc)

    bug9110 = '[ruby-core:58329][Bug #9110]'
    assert_ruby_status([], "#{<<~"begin;"}\n#{<<~'end;'}", bug9110)
    begin;
      require "continuation"
      c = nil
      at_exit { c.call }
      at_exit { callcc {|_c| c = _c } }
    end;
  end

  def test_errinfo_at_exit
    bug12302 = '[ruby-core:75038] [Bug #12302]'
    assert_in_out_err([], "#{<<~"begin;"}\n#{<<~'end;'}", %w[2:exit 1:exit], [], bug12302)
    begin;
      at_exit do
        puts "1:#{$!}"
      end

      at_exit do
        puts "2:#{$!}"
        raise 'x' rescue nil
      end

      at_exit do
        exit
      end
    end;
  end

  if defined?(fork)
    def test_internal_errinfo_at_exit
      # TODO: use other than break-in-fork to throw an internal
      # error info.
      error, pid, status = IO.pipe do |r, w|
        pid = fork do
          r.close
          STDERR.reopen(w)
          at_exit do
            $!.class
          end
          break
        end
        w.close
        [r.read, *Process.wait2(pid)]
      end
      assert_not_predicate(status, :success?)
      assert_not_predicate(status, :signaled?)
      assert_match(/unexpected break/, error)
    end
  end
end
