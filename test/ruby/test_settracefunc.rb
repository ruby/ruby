require 'test/unit'

class TestSetTraceFunc < Test::Unit::TestCase
  def foo; end

  def test_event
    events = []
    set_trace_func(Proc.new { |event, file, lineno, mid, bidning, klass|
      events << [event, lineno, mid, klass]
    })
    a = 1
    foo
    a
    b = 1 + 2
    if b == 3
      case b
      when 2
        c = "b == 2"
      when 3
        c = "b == 3"
      end
    end
    begin
      raise "error"
    rescue
    end
    eval("class Foo; end")
    set_trace_func nil

    assert_equal(["line", 11, :test_event, TestSetTraceFunc],
                 events.shift)     # a = 1
    assert_equal(["line", 12, :test_event, TestSetTraceFunc],
                 events.shift)     # foo
    assert_equal(["call", 4, :foo, TestSetTraceFunc],
                 events.shift)     # foo
    assert_equal(["return", 4, :foo, TestSetTraceFunc],
                 events.shift)     # foo
    assert_equal(["line", 13, :test_event, TestSetTraceFunc],
                 events.shift)     # a
    assert_equal(["line", 14, :test_event, TestSetTraceFunc],
                 events.shift)     # b = 1 + 2
    assert_equal(["c-call", 14, :+, Fixnum],
                 events.shift)     # 1 + 2
    assert_equal(["c-return", 14, :+, Fixnum],
                 events.shift)     # 1 + 2
    assert_equal(["line", 15, :test_event, TestSetTraceFunc],
                 events.shift)     # if b == 3
    assert_equal(["line", 15, :test_event, TestSetTraceFunc],
                 events.shift)     # if b == 3
    assert_equal(["c-call", 15, :==, Fixnum],
                 events.shift)     # b == 3
    assert_equal(["c-return", 15, :==, Fixnum],
                 events.shift)     # b == 3
    assert_equal(["line", 16, :test_event, TestSetTraceFunc],
                 events.shift)     # case b
    assert_equal(["line", 17, :test_event, TestSetTraceFunc],
                 events.shift)     # when 2
    assert_equal(["c-call", 17, :===, Kernel],
                 events.shift)     # when 2
    assert_equal(["c-call", 17, :==, Fixnum],
                 events.shift)     # when 2
    assert_equal(["c-return", 17, :==, Fixnum],
                 events.shift)     # when 2
    assert_equal(["c-return", 17, :===, Kernel],
                 events.shift)     # when 2
    assert_equal(["line", 19, :test_event, TestSetTraceFunc],
                 events.shift)     # when 3
    assert_equal(["c-call", 19, :===, Kernel],
                 events.shift)     # when 3
    assert_equal(["c-return", 19, :===, Kernel],
                 events.shift)     # when 3
    assert_equal(["line", 20, :test_event, TestSetTraceFunc],
                 events.shift)     # c = "b == 3"
    assert_equal(["line", 23, :test_event, TestSetTraceFunc],
                 events.shift)     # begin
    assert_equal(["line", 24, :test_event, TestSetTraceFunc],
                 events.shift)     # raise "error"
    assert_equal(["c-call", 24, :raise, Kernel],
                 events.shift)     # raise "error"
    assert_equal(["c-call", 24, :new, Class],
                 events.shift)     # raise "error"
    assert_equal(["c-call", 24, :initialize, Exception],
                 events.shift)     # raise "error"
    assert_equal(["c-return", 24, :initialize, Exception],
                 events.shift)     # raise "error"
    assert_equal(["c-return", 24, :new, Class],
                 events.shift)     # raise "error"
    assert_equal(["c-call", 24, :backtrace, Exception],
                 events.shift)     # raise "error"
    assert_equal(["c-return", 24, :backtrace, Exception],
                 events.shift)     # raise "error"
    assert_equal(["c-call", 24, :set_backtrace, Exception],
                 events.shift)     # raise "error"
    assert_equal(["c-return", 24, :set_backtrace, Exception],
                 events.shift)     # raise "error"
    assert_equal(["raise", 24, :test_event, TestSetTraceFunc],
                 events.shift)     # raise "error"
    assert_equal(["c-return", 24, :raise, Kernel],
                 events.shift)     # raise "error"
    assert_equal(["line", 27, :test_event, TestSetTraceFunc],
                 events.shift)     # eval(<<EOF)
    assert_equal(["c-call", 27, :eval, Kernel],
                 events.shift)     # eval(<<EOF)
    assert_equal(["line", 1, :test_event, TestSetTraceFunc],
                 events.shift)     # class Foo
    assert_equal(["c-call", 1, :inherited, Class],
                 events.shift)     # class Foo
    assert_equal(["c-return", 1, :inherited, Class],
                 events.shift)     # class Foo
    assert_equal(["class", 1, :test_event, TestSetTraceFunc],
                 events.shift)     # class Foo
    assert_equal(["end", 1, :test_event, TestSetTraceFunc],
                 events.shift)     # class Foo
    assert_equal(["c-return", 27, :eval, Kernel],
                 events.shift)     # eval(<<EOF)
    assert_equal(["line", 28, :test_event, TestSetTraceFunc],
                 events.shift)     # set_trace_func nil
    assert_equal(["c-call", 28, :set_trace_func, Kernel],
                 events.shift)     # set_trace_func nil
    assert_equal([], events)
  end
end
