require 'test/unit'

class TestSetTraceFunc < Test::Unit::TestCase
  def foo; end

  def test_event
    events = []
    set_trace_func(Proc.new { |event, file, lineno|
      events << [event, lineno]
    })
    a = 1
    foo
    a
    b = 1 + 2
    set_trace_func nil

    assert_equal(["line", 11], events.shift)     # line "a = 1"
    assert_equal(["line", 12], events.shift)     # line "foo"
    assert_equal(["call", 4], events.shift)      # call foo
    assert_equal(["return", 4], events.shift)    # return foo
    assert_equal(["line", 13], events.shift)     # line "a"
    assert_equal(["line", 14], events.shift)     # line "b = 1 + 2"
    assert_equal(["c-call", 14], events.shift)   # c-call Fixnum#+
    assert_equal(["c-return", 14], events.shift) # c-return Fixnum#+
    assert_equal(["line", 15], events.shift)     # line "set_trace_func nil"
    assert_equal(["c-call", 15], events.shift)   # c-call set_trace_func
  end
end
