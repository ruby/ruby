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
    set_trace_func nil

    assert_equal(["line", 11], events.shift)    # line "a = 1"
    assert_equal(["line", 12], events.shift)    # line "foo"
    assert_equal(["call", 4], events.shift)     # call foo
    event, lineno = events.shift                # return
      assert_equal("return", event)
      assert_not_equal(4, lineno)# it should be 4 but cannot be expected in 1.8
    assert_equal(["line", 13], events.shift)    # line "a"
    assert_equal(["line", 14], events.shift)    # line "set_trace_func nil"
    assert_equal(["c-call", 14], events.shift)  # c-call set_trace_func
  end
end
