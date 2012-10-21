require 'test/unit'

class TestSetTraceFunc < Test::Unit::TestCase
  def setup
    @original_compile_option = RubyVM::InstructionSequence.compile_option
    RubyVM::InstructionSequence.compile_option = {
      :trace_instruction => true,
      :specialized_instruction => false
    }
  end

  def teardown
    set_trace_func(nil)
    RubyVM::InstructionSequence.compile_option = @original_compile_option
  end

  def test_c_call
    events = []
    name = "#{self.class}\##{__method__}"
    eval <<-EOF.gsub(/^.*?: /, ""), nil, name
     1: set_trace_func(Proc.new { |event, file, lineno, mid, binding, klass|
     2:   events << [event, lineno, mid, klass] if file == name
     3: })
     4: x = 1 + 1
     5: set_trace_func(nil)
    EOF
    assert_equal(["c-return", 1, :set_trace_func, Kernel],
                 events.shift)
    assert_equal(["line", 4, __method__, self.class],
                 events.shift)
    assert_equal(["c-call", 4, :+, Fixnum],
                 events.shift)
    assert_equal(["c-return", 4, :+, Fixnum],
                 events.shift)
    assert_equal(["line", 5, __method__, self.class],
                 events.shift)
    assert_equal(["c-call", 5, :set_trace_func, Kernel],
                 events.shift)
    assert_equal([], events)
  end

  def test_call
    events = []
    name = "#{self.class}\##{__method__}"
    eval <<-EOF.gsub(/^.*?: /, ""), nil, name
     1: set_trace_func(Proc.new { |event, file, lineno, mid, binding, klass|
     2:   events << [event, lineno, mid, klass] if file == name
     3: })
     4: def add(x, y)
     5:   x + y
     6: end
     7: x = add(1, 1)
     8: set_trace_func(nil)
    EOF
    assert_equal(["c-return", 1, :set_trace_func, Kernel],
                 events.shift)
    assert_equal(["line", 4, __method__, self.class],
                 events.shift)
    assert_equal(["c-call", 4, :method_added, self.class],
                 events.shift)
    assert_equal(["c-return", 4, :method_added, self.class],
                 events.shift)
    assert_equal(["line", 7, __method__, self.class],
                 events.shift)
    assert_equal(["call", 4, :add, self.class],
                 events.shift)
    assert_equal(["line", 5, :add, self.class],
                 events.shift)
    assert_equal(["c-call", 5, :+, Fixnum],
                 events.shift)
    assert_equal(["c-return", 5, :+, Fixnum],
                 events.shift)
    assert_equal(["return", 6, :add, self.class],
                 events.shift)
    assert_equal(["line", 8, __method__, self.class],
                 events.shift)
    assert_equal(["c-call", 8, :set_trace_func, Kernel],
                 events.shift)
    assert_equal([], events)
  end

  def test_class
    events = []
    name = "#{self.class}\##{__method__}"
    eval <<-EOF.gsub(/^.*?: /, ""), nil, name
     1: set_trace_func(Proc.new { |event, file, lineno, mid, binding, klass|
     2:   events << [event, lineno, mid, klass] if file == name
     3: })
     4: class Foo
     5:   def bar
     6:   end
     7: end
     8: x = Foo.new.bar
     9: set_trace_func(nil)
    EOF
    assert_equal(["c-return", 1, :set_trace_func, Kernel],
                 events.shift)
    assert_equal(["line", 4, __method__, self.class],
                 events.shift)
    assert_equal(["c-call", 4, :inherited, Class],
                 events.shift)
    assert_equal(["c-return", 4, :inherited, Class],
                 events.shift)
    assert_equal(["class", 4, nil, nil],
                 events.shift)
    assert_equal(["line", 5, nil, nil],
                 events.shift)
    assert_equal(["c-call", 5, :method_added, Module],
                 events.shift)
    assert_equal(["c-return", 5, :method_added, Module],
                 events.shift)
    assert_equal(["end", 7, nil, nil],
                 events.shift)
    assert_equal(["line", 8, __method__, self.class],
                 events.shift)
    assert_equal(["c-call", 8, :new, Class],
                 events.shift)
    assert_equal(["c-call", 8, :initialize, BasicObject],
                 events.shift)
    assert_equal(["c-return", 8, :initialize, BasicObject],
                 events.shift)
    assert_equal(["c-return", 8, :new, Class],
                 events.shift)
    assert_equal(["call", 5, :bar, Foo],
                 events.shift)
    assert_equal(["return", 6, :bar, Foo],
                 events.shift)
    assert_equal(["line", 9, __method__, self.class],
                 events.shift)
    assert_equal(["c-call", 9, :set_trace_func, Kernel],
                 events.shift)
    assert_equal([], events)
  end

  def test_return # [ruby-dev:38701]
    events = []
    name = "#{self.class}\##{__method__}"
    eval <<-EOF.gsub(/^.*?: /, ""), nil, name
     1: set_trace_func(Proc.new { |event, file, lineno, mid, binding, klass|
     2:   events << [event, lineno, mid, klass] if file == name
     3: })
     4: def foo(a)
     5:   return if a
     6:   return
     7: end
     8: foo(true)
     9: foo(false)
    10: set_trace_func(nil)
    EOF
    assert_equal(["c-return", 1, :set_trace_func, Kernel],
                 events.shift)
    assert_equal(["line", 4, __method__, self.class],
                 events.shift)
    assert_equal(["c-call", 4, :method_added, self.class],
                 events.shift)
    assert_equal(["c-return", 4, :method_added, self.class],
                 events.shift)
    assert_equal(["line", 8, __method__, self.class],
                 events.shift)
    assert_equal(["call", 4, :foo, self.class],
                 events.shift)
    assert_equal(["line", 5, :foo, self.class],
                 events.shift)
    assert_equal(["return", 5, :foo, self.class],
                 events.shift)
    assert_equal(["line", 9, :test_return, self.class],
                 events.shift)
    assert_equal(["call", 4, :foo, self.class],
                 events.shift)
    assert_equal(["line", 5, :foo, self.class],
                 events.shift)
    assert_equal(["return", 7, :foo, self.class],
                 events.shift)
    assert_equal(["line", 10, :test_return, self.class],
                 events.shift)
    assert_equal(["c-call", 10, :set_trace_func, Kernel],
                 events.shift)
    assert_equal([], events)
  end

  def test_return2 # [ruby-core:24463]
    events = []
    name = "#{self.class}\##{__method__}"
    eval <<-EOF.gsub(/^.*?: /, ""), nil, name
     1: set_trace_func(Proc.new { |event, file, lineno, mid, binding, klass|
     2:   events << [event, lineno, mid, klass] if file == name
     3: })
     4: def foo
     5:   a = 5
     6:   return a
     7: end
     8: foo
     9: set_trace_func(nil)
    EOF
    assert_equal(["c-return", 1, :set_trace_func, Kernel],
                 events.shift)
    assert_equal(["line", 4, __method__, self.class],
                 events.shift)
    assert_equal(["c-call", 4, :method_added, self.class],
                 events.shift)
    assert_equal(["c-return", 4, :method_added, self.class],
                 events.shift)
    assert_equal(["line", 8, __method__, self.class],
                 events.shift)
    assert_equal(["call", 4, :foo, self.class],
                 events.shift)
    assert_equal(["line", 5, :foo, self.class],
                 events.shift)
    assert_equal(["line", 6, :foo, self.class],
                 events.shift)
    assert_equal(["return", 7, :foo, self.class],
                 events.shift)
    assert_equal(["line", 9, :test_return2, self.class],
                 events.shift)
    assert_equal(["c-call", 9, :set_trace_func, Kernel],
                 events.shift)
    assert_equal([], events)
  end

  def test_raise
    events = []
    name = "#{self.class}\##{__method__}"
    eval <<-EOF.gsub(/^.*?: /, ""), nil, name
     1: set_trace_func(Proc.new { |event, file, lineno, mid, binding, klass|
     2:   events << [event, lineno, mid, klass] if file == name
     3: })
     4: begin
     5:   raise TypeError, "error"
     6: rescue TypeError
     7: end
     8: set_trace_func(nil)
    EOF
    assert_equal(["c-return", 1, :set_trace_func, Kernel],
                 events.shift)
    assert_equal(["line", 4, __method__, self.class],
                 events.shift)
    assert_equal(["line", 5, __method__, self.class],
                 events.shift)
    assert_equal(["c-call", 5, :raise, Kernel],
                 events.shift)
    assert_equal(["c-call", 5, :exception, Exception],
                 events.shift)
    assert_equal(["c-call", 5, :initialize, Exception],
                 events.shift)
    assert_equal(["c-return", 5, :initialize, Exception],
                 events.shift)
    assert_equal(["c-return", 5, :exception, Exception],
                 events.shift)
    assert_equal(["c-call", 5, :backtrace, Exception],
                 events.shift)
    assert_equal(["c-return", 5, :backtrace, Exception],
                 events.shift)
    assert_equal(["raise", 5, :test_raise, TestSetTraceFunc],
                 events.shift)
    assert_equal(["c-return", 5, :raise, Kernel],
                 events.shift)
    assert_equal(["c-call", 6, :===, Module],
                 events.shift)
    assert_equal(["c-return", 6, :===, Module],
                 events.shift)
    assert_equal(["line", 8, __method__, self.class],
                 events.shift)
    assert_equal(["c-call", 8, :set_trace_func, Kernel],
                 events.shift)
    assert_equal([], events)
  end

  def test_break # [ruby-core:27606] [Bug #2610]
    events = []
    name = "#{self.class}\##{__method__}"
    eval <<-EOF.gsub(/^.*?: /, ""), nil, name
     1: set_trace_func(Proc.new { |event, file, lineno, mid, binding, klass|
     2:   events << [event, lineno, mid, klass] if file == name
     3: })
     4: [1,2,3].any? {|n| n}
     8: set_trace_func(nil)
    EOF

    [["c-return", 1, :set_trace_func, Kernel],
     ["line", 4, __method__, self.class],
     ["c-call", 4, :any?, Enumerable],
     ["c-call", 4, :each, Array],
     ["line", 4, __method__, self.class],
     ["c-return", 4, :each, Array],
     ["c-return", 4, :any?, Enumerable],
     ["line", 5, __method__, self.class],
     ["c-call", 5, :set_trace_func, Kernel]].each{|e|
      assert_equal(e, events.shift)
    }
  end

  def test_invalid_proc
      assert_raise(TypeError) { set_trace_func(1) }
  end

  def test_raise_in_trace
    set_trace_func proc {raise rescue nil}
    assert_equal(42, (raise rescue 42), '[ruby-core:24118]')
  end

  def test_thread_trace
    events = {:set => [], :add => []}
    prc = Proc.new { |event, file, lineno, mid, binding, klass|
      events[:set] << [event, lineno, mid, klass, :set]
    }
    prc2 = Proc.new { |event, file, lineno, mid, binding, klass|
      events[:add] << [event, lineno, mid, klass, :add]
    }

    th = Thread.new do
      th = Thread.current
      name = "#{self.class}\##{__method__}"
      eval <<-EOF.gsub(/^.*?: /, ""), nil, name
       1: th.set_trace_func(prc)
       2: th.add_trace_func(prc2)
       3: class ThreadTraceInnerClass
       4:   def foo
       5:     x = 1 + 1
       6:   end
       7: end
       8: ThreadTraceInnerClass.new.foo
       9: th.set_trace_func(nil)
      EOF
    end
    th.join

    [["c-return", 1, :set_trace_func, Thread, :set],
     ["line", 2, __method__, self.class, :set],
     ["c-call", 2, :add_trace_func, Thread, :set]].each do |e|
      assert_equal(e, events[:set].shift)
    end

    [["c-return", 2, :add_trace_func, Thread],
     ["line", 3, __method__, self.class],
     ["c-call", 3, :inherited, Class],
     ["c-return", 3, :inherited, Class],
     ["class", 3, nil, nil],
     ["line", 4, nil, nil],
     ["c-call", 4, :method_added, Module],
     ["c-return", 4, :method_added, Module],
     ["end", 7, nil, nil],
     ["line", 8, __method__, self.class],
     ["c-call", 8, :new, Class],
     ["c-call", 8, :initialize, BasicObject],
     ["c-return", 8, :initialize, BasicObject],
     ["c-return", 8, :new, Class],
     ["call", 4, :foo, ThreadTraceInnerClass],
     ["line", 5, :foo, ThreadTraceInnerClass],
     ["c-call", 5, :+, Fixnum],
     ["c-return", 5, :+, Fixnum],
     ["return", 6, :foo, ThreadTraceInnerClass],
     ["line", 9, __method__, self.class],
     ["c-call", 9, :set_trace_func, Thread]].each do |e|
      [:set, :add].each do |type|
        assert_equal(e + [type], events[type].shift)
      end
    end
    assert_equal([], events[:set])
    assert_equal([], events[:add])
  end

  def test_trace_defined_method
    events = []
    name = "#{self.class}\##{__method__}"
    eval <<-EOF.gsub(/^.*?: /, ""), nil, name
     1: class FooBar; define_method(:foobar){}; end
     2: fb = FooBar.new
     3: set_trace_func(Proc.new { |event, file, lineno, mid, binding, klass|
     4:   events << [event, lineno, mid, klass] if file == name
     5: })
     6: fb.foobar
     7: set_trace_func(nil)
    EOF

    [["c-return", 3, :set_trace_func, Kernel],
     ["line", 6, __method__, self.class],
     ["call", 6, :foobar, FooBar],
     ["return", 6, :foobar, FooBar],
     ["line", 7, __method__, self.class],
     ["c-call", 7, :set_trace_func, Kernel]].each{|e|
      assert_equal(e, events.shift)
    }
  end

  def test_remove_in_trace
    bug3921 = '[ruby-dev:42350]'
    ok = false
    func = lambda{|e, f, l, i, b, k|
      set_trace_func(nil)
      ok = eval("self", b)
    }

    set_trace_func(func)
    assert_equal(self, ok, bug3921)
  end

  class << self
    define_method(:method_added, Module.method(:method_added))
  end

  def trace_by_tracepoint *trace_events
    events = []
    trace = nil
    xyzzy = nil
    local_var = :outer
    method = :trace_by_tracepoint

    eval <<-EOF.gsub(/^.*?: /, ""), nil, 'xyzzy'
    1: trace = TracePoint.trace(*trace_events){|tp|
    2:   events << [tp.event, tp.line, tp.file, tp.klass, tp.id, tp.self, tp.binding.eval("local_var")]
    3: }
    4: 1.times{|;local_var| local_var = :inner
    5:   tap{}
    6: }
    7: class XYZZY
    8:   local_var = :XYZZY_outer
    9:   def foo
   10:     local_var = :XYZZY_foo
   11:     bar
   12:   end
   13:   def bar
   14:     local_var = :XYZZY_bar
   15:     tap{}
   16:   end
   17: end
   18: xyzzy = XYZZY.new
   19: xyzzy.foo
   20: trace.untrace
    EOF
    self.class.class_eval{remove_const(:XYZZY)}

    answer_events = [
     #
     [:c_return, 1, "xyzzy", TracePoint,  :trace,           TracePoint, :outer],
     [:line,     4, 'xyzzy', self.class,  method,           self, :outer],
     [:c_call,   4, 'xyzzy', Integer,     :times,           1,    :outer],
     [:line,     4, 'xyzzy', self.class,  method,           self, nil],
     [:line,     5, 'xyzzy', self.class,  method,           self, :inner],
     [:c_call,   5, 'xyzzy', Kernel,      :tap,             self, :inner],
     [:c_return, 5, "xyzzy", Kernel,      :tap,             self, :inner],
     [:c_return, 4, "xyzzy", Integer,     :times,           1,    :outer],
     [:line,     7, 'xyzzy', self.class,  method,           self, :outer],
     [:c_call,   7, "xyzzy", Class,       :inherited,       Object, :outer],
     [:c_return, 7, "xyzzy", Class,       :inherited,       Object, :outer],
     [:class,    7, "xyzzy", nil,         nil,              xyzzy.class, nil],
     [:line,     8, "xyzzy", nil,         nil,              xyzzy.class, nil],
     [:line,     9, "xyzzy", nil,         nil,              xyzzy.class, :XYZZY_outer],
     [:c_call,   9, "xyzzy", Module,      :method_added,    xyzzy.class, :XYZZY_outer],
     [:c_return, 9, "xyzzy", Module,      :method_added,    xyzzy.class, :XYZZY_outer],
     [:line,    13, "xyzzy", nil,         nil,              xyzzy.class, :XYZZY_outer],
     [:c_call,  13, "xyzzy", Module,      :method_added,    xyzzy.class, :XYZZY_outer],
     [:c_return,13, "xyzzy", Module,      :method_added,    xyzzy.class, :XYZZY_outer],
     [:end,     17, "xyzzy", nil,         nil,              xyzzy.class, :XYZZY_outer],
     [:line,    18, "xyzzy", TestSetTraceFunc, method,      self, :outer],
     [:c_call,  18, "xyzzy", Class,       :new,             xyzzy.class, :outer],
     [:c_call,  18, "xyzzy", BasicObject, :initialize,      xyzzy, :outer],
     [:c_return,18, "xyzzy", BasicObject, :initialize,      xyzzy, :outer],
     [:c_return,18, "xyzzy", Class,       :new,             xyzzy.class, :outer],
     [:line,    19, "xyzzy", TestSetTraceFunc, method,      self, :outer],
     [:call,     9, "xyzzy", xyzzy.class, :foo,             xyzzy, nil],
     [:line,    10, "xyzzy", xyzzy.class, :foo,             xyzzy, nil],
     [:line,    11, "xyzzy", xyzzy.class, :foo,             xyzzy, :XYZZY_foo],
     [:call,    13, "xyzzy", xyzzy.class, :bar,             xyzzy, nil],
     [:line,    14, "xyzzy", xyzzy.class, :bar,             xyzzy, nil],
     [:line,    15, "xyzzy", xyzzy.class, :bar,             xyzzy, :XYZZY_bar],
     [:c_call,  15, "xyzzy", Kernel,      :tap,             xyzzy, :XYZZY_bar],
     [:c_return,15, "xyzzy", Kernel,      :tap,             xyzzy, :XYZZY_bar],
     [:return,  16, "xyzzy", xyzzy.class, :bar,             xyzzy, :XYZZY_bar],
     [:return,  12, "xyzzy", xyzzy.class, :foo,             xyzzy, :XYZZY_foo],
     [:line,    20, "xyzzy", TestSetTraceFunc, method,      self, :outer],
     [:c_call,  20, "xyzzy", TracePoint,  :untrace,         trace, :outer],
     ]

    return events, answer_events
  end

  def trace_by_set_trace_func
    events = []
    trace = nil
    xyzzy = nil
    local_var = :outer
    eval <<-EOF.gsub(/^.*?: /, ""), nil, 'xyzzy'
    1: set_trace_func(lambda{|event, file, line, id, binding, klass|
    2:   events << [event, line, file, klass, id, binding.eval('self'), binding.eval("local_var")]
    3: })
    4: 1.times{|;local_var| local_var = :inner
    5:   tap{}
    6: }
    7: class XYZZY
    8:   local_var = :XYZZY_outer
    9:   def foo
   10:     local_var = :XYZZY_foo
   11:     bar
   12:   end
   13:   def bar
   14:     local_var = :XYZZY_bar
   15:     tap{}
   16:   end
   17: end
   18: xyzzy = XYZZY.new
   19: xyzzy.foo
   20: set_trace_func(nil)
    EOF
    self.class.class_eval{remove_const(:XYZZY)}
    return events
  end

  def test_tracepoint
    events1, answer_events = *trace_by_tracepoint()
    answer_events.zip(events1){|answer, event|
      assert_equal answer, event
    }

    events2 = trace_by_set_trace_func
    events1.zip(events2){|ev1, ev2|
      ev2[0] = ev2[0].sub('-', '_').to_sym
      assert_equal ev1[0..2], ev2[0..2], ev1.inspect

      # event, line, file, klass, id, binding.eval('self'), binding.eval("local_var")
      assert_equal ev1[3].nil?, ev2[3].nil? # klass
      assert_equal ev1[4].nil?, ev2[4].nil? # id
      assert_equal ev1[6], ev2[6]           # local_var
    }

    [:line, :class, :end, :call, :return, :c_call, :c_return, :raise].each{|event|
      events1, answer_events = *trace_by_tracepoint(event)
      answer_events.find_all{|e| e[0] == event}.zip(events1){|answer_line, event_line|
        assert_equal answer_line, event_line
      }
    }
  end

  def test_tracepoint_object_id
    tps = []
    trace = TracePoint.trace(){|tp|
      tps << tp
    }
    tap{}
    tap{}
    tap{}
    trace.untrace

    # passed tp is unique, `trace' object which is genereted by TracePoint.trace
    tps.each{|tp|
      assert_equal trace, tp
    }
  end

  def test_tracepoint_access_from_outside
    tp_store = nil
    trace = TracePoint.trace(){|tp|
      tp_store = tp
    }
    tap{}
    trace.untrace

    assert_raise(RuntimeError){tp_store.line}
    assert_raise(RuntimeError){tp_store.event}
    assert_raise(RuntimeError){tp_store.file}
    assert_raise(RuntimeError){tp_store.id}
    assert_raise(RuntimeError){tp_store.klass}
    assert_raise(RuntimeError){tp_store.binding}
    assert_raise(RuntimeError){tp_store.self}
  end
end
