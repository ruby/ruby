require 'test/unit'
require_relative 'envutil'

class TestSetTraceFunc < Test::Unit::TestCase
  def setup
    @original_compile_option = RubyVM::InstructionSequence.compile_option
    RubyVM::InstructionSequence.compile_option = {
      :trace_instruction => true,
      :specialized_instruction => false
    }
    @target_thread = Thread.current
  end

  def teardown
    set_trace_func(nil)
    RubyVM::InstructionSequence.compile_option = @original_compile_option
    @target_thread = nil
  end

  def target_thread?
    Thread.current == @target_thread
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
     4: def meth_return(a)
     5:   return if a
     6:   return
     7: end
     8: meth_return(true)
     9: meth_return(false)
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
    assert_equal(["call", 4, :meth_return, self.class],
                 events.shift)
    assert_equal(["line", 5, :meth_return, self.class],
                 events.shift)
    assert_equal(["return", 5, :meth_return, self.class],
                 events.shift)
    assert_equal(["line", 9, :test_return, self.class],
                 events.shift)
    assert_equal(["call", 4, :meth_return, self.class],
                 events.shift)
    assert_equal(["line", 5, :meth_return, self.class],
                 events.shift)
    assert_equal(["return", 7, :meth_return, self.class],
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
     4: def meth_return2
     5:   a = 5
     6:   return a
     7: end
     8: meth_return2
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
    assert_equal(["call", 4, :meth_return2, self.class],
                 events.shift)
    assert_equal(["line", 5, :meth_return2, self.class],
                 events.shift)
    assert_equal(["line", 6, :meth_return2, self.class],
                 events.shift)
    assert_equal(["return", 7, :meth_return2, self.class],
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
    prc = prc # suppress warning
    prc2 = Proc.new { |event, file, lineno, mid, binding, klass|
      events[:add] << [event, lineno, mid, klass, :add]
    }
    prc2 = prc2 # suppress warning

    th = Thread.new do
      th = Thread.current
      name = "#{self.class}\##{__method__}"
      eval <<-EOF.gsub(/^.*?: /, ""), nil, name
       1: th.set_trace_func(prc)
       2: th.add_trace_func(prc2)
       3: class ThreadTraceInnerClass
       4:   def foo
       5:     _x = 1 + 1
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

  def assert_security_error_safe4(block)
    assert_raise(SecurityError) do
      block.call
    end
  end

  def test_set_safe4
    func = proc do
      $SAFE = 4
      set_trace_func(lambda {|*|})
    end
    assert_security_error_safe4(func)
  end

  def test_thread_set_safe4
    th = Thread.start {sleep}
    func = proc do
      $SAFE = 4
      th.set_trace_func(lambda {|*|})
    end
    assert_security_error_safe4(func)
  ensure
    th.kill
  end

  def test_thread_add_safe4
    th = Thread.start {sleep}
    func = proc do
      $SAFE = 4
      th.add_trace_func(lambda {|*|})
    end
    assert_security_error_safe4(func)
  ensure
    th.kill
  end

  class << self
    define_method(:method_added, Module.method(:method_added))
  end

  def trace_by_tracepoint *trace_events
    events = []
    trace = nil
    xyzzy = nil
    _local_var = :outer
    raised_exc = nil
    method = :trace_by_tracepoint
    _get_data = lambda{|tp|
      case tp.event
      when :return, :c_return
        tp.return_value
      when :raise
        tp.raised_exception
      else
        :nothing
      end
    }
    _defined_class = lambda{|tp|
      klass = tp.defined_class
      begin
        # If it is singleton method, then return original class
        # to make compatible with set_trace_func().
        # This is very ad-hoc hack. I hope I can make more clean test on it.
        case klass.inspect
        when /Class:TracePoint/; return TracePoint
        when /Class:Exception/; return Exception
        else klass
        end
      rescue Exception => e
        e
      end if klass
    }

    trace = nil
    begin
    eval <<-EOF.gsub(/^.*?: /, ""), nil, 'xyzzy'
    1: trace = TracePoint.trace(*trace_events){|tp|
    2:   events << [tp.event, tp.lineno, tp.path, _defined_class.(tp), tp.method_id, tp.self, tp.binding.eval("_local_var"), _get_data.(tp)] if tp.path == 'xyzzy'
    3: }
    4: 1.times{|;_local_var| _local_var = :inner
    5:   tap{}
    6: }
    7: class XYZZY
    8:   _local_var = :XYZZY_outer
    9:   def foo
   10:     _local_var = :XYZZY_foo
   11:     bar
   12:   end
   13:   def bar
   14:     _local_var = :XYZZY_bar
   15:     tap{}
   16:   end
   17: end
   18: xyzzy = XYZZY.new
   19: xyzzy.foo
   20: begin; raise RuntimeError; rescue RuntimeError => raised_exc; end
   21: trace.disable
    EOF
    self.class.class_eval{remove_const(:XYZZY)}
    ensure
      trace.disable if trace && trace.enabled?
    end

    answer_events = [
     #
     [:c_return, 1, "xyzzy", TracePoint,  :trace,           TracePoint,  :outer,  trace],
     [:line,     4, 'xyzzy', self.class,  method,           self,        :outer, :nothing],
     [:c_call,   4, 'xyzzy', Integer,     :times,           1,           :outer, :nothing],
     [:line,     4, 'xyzzy', self.class,  method,           self,        nil,    :nothing],
     [:line,     5, 'xyzzy', self.class,  method,           self,        :inner, :nothing],
     [:c_call,   5, 'xyzzy', Kernel,      :tap,             self,        :inner, :nothing],
     [:c_return, 5, "xyzzy", Kernel,      :tap,             self,        :inner, self],
     [:c_return, 4, "xyzzy", Integer,     :times,           1,           :outer, 1],
     [:line,     7, 'xyzzy', self.class,  method,           self,        :outer, :nothing],
     [:c_call,   7, "xyzzy", Class,       :inherited,       Object,      :outer, :nothing],
     [:c_return, 7, "xyzzy", Class,       :inherited,       Object,      :outer, nil],
     [:class,    7, "xyzzy", nil,         nil,              xyzzy.class, nil,    :nothing],
     [:line,     8, "xyzzy", nil,         nil,              xyzzy.class, nil,    :nothing],
     [:line,     9, "xyzzy", nil,         nil,              xyzzy.class, :XYZZY_outer, :nothing],
     [:c_call,   9, "xyzzy", Module,      :method_added,    xyzzy.class, :XYZZY_outer, :nothing],
     [:c_return, 9, "xyzzy", Module,      :method_added,    xyzzy.class, :XYZZY_outer, nil],
     [:line,    13, "xyzzy", nil,         nil,              xyzzy.class, :XYZZY_outer, :nothing],
     [:c_call,  13, "xyzzy", Module,      :method_added,    xyzzy.class, :XYZZY_outer, :nothing],
     [:c_return,13, "xyzzy", Module,      :method_added,    xyzzy.class, :XYZZY_outer, nil],
     [:end,     17, "xyzzy", nil,         nil,              xyzzy.class, :XYZZY_outer, :nothing],
     [:line,    18, "xyzzy", TestSetTraceFunc, method,      self,        :outer, :nothing],
     [:c_call,  18, "xyzzy", Class,       :new,             xyzzy.class, :outer, :nothing],
     [:c_call,  18, "xyzzy", BasicObject, :initialize,      xyzzy,       :outer, :nothing],
     [:c_return,18, "xyzzy", BasicObject, :initialize,      xyzzy,       :outer, nil],
     [:c_return,18, "xyzzy", Class,       :new,             xyzzy.class, :outer, xyzzy],
     [:line,    19, "xyzzy", TestSetTraceFunc, method,      self, :outer, :nothing],
     [:call,     9, "xyzzy", xyzzy.class, :foo,             xyzzy,       nil,  :nothing],
     [:line,    10, "xyzzy", xyzzy.class, :foo,             xyzzy,       nil,  :nothing],
     [:line,    11, "xyzzy", xyzzy.class, :foo,             xyzzy,       :XYZZY_foo, :nothing],
     [:call,    13, "xyzzy", xyzzy.class, :bar,             xyzzy,       nil, :nothing],
     [:line,    14, "xyzzy", xyzzy.class, :bar,             xyzzy,       nil, :nothing],
     [:line,    15, "xyzzy", xyzzy.class, :bar,             xyzzy,       :XYZZY_bar, :nothing],
     [:c_call,  15, "xyzzy", Kernel,      :tap,             xyzzy,       :XYZZY_bar, :nothing],
     [:c_return,15, "xyzzy", Kernel,      :tap,             xyzzy,       :XYZZY_bar, xyzzy],
     [:return,  16, "xyzzy", xyzzy.class, :bar,             xyzzy,       :XYZZY_bar, xyzzy],
     [:return,  12, "xyzzy", xyzzy.class, :foo,             xyzzy,       :XYZZY_foo, xyzzy],
     [:line,    20, "xyzzy", TestSetTraceFunc, method,      self,        :outer, :nothing],
     [:line,    20, "xyzzy", TestSetTraceFunc, method,      self,        :outer, :nothing],
     [:c_call,  20, "xyzzy", Kernel,      :raise,           self,        :outer, :nothing],
     [:c_call,  20, "xyzzy", Exception,   :exception,       RuntimeError, :outer, :nothing],
     [:c_call,  20, "xyzzy", Exception,   :initialize,      raised_exc,  :outer, :nothing],
     [:c_return,20, "xyzzy", Exception,   :initialize,      raised_exc,  :outer, raised_exc],
     [:c_return,20, "xyzzy", Exception,   :exception,       RuntimeError, :outer, raised_exc],
     [:c_call,  20, "xyzzy", Exception,   :backtrace,       raised_exc,  :outer, :nothing],
     [:c_return,20, "xyzzy", Exception,   :backtrace,       raised_exc,  :outer, nil],
     [:raise,   20, "xyzzy", TestSetTraceFunc, :trace_by_tracepoint, self, :outer, raised_exc],
     [:c_return,20, "xyzzy", Kernel,      :raise,           self,        :outer, nil],
     [:c_call,  20, "xyzzy", Module,      :===,             RuntimeError,:outer, :nothing],
     [:c_return,20, "xyzzy", Module,      :===,             RuntimeError,:outer, true],
     [:line,    21, "xyzzy", TestSetTraceFunc, method,      self,        :outer, :nothing],
     [:c_call,  21, "xyzzy", TracePoint,  :disable,         trace,       :outer, :nothing],
     ]

    return events, answer_events
  end

  def trace_by_set_trace_func
    events = []
    trace = nil
    trace = trace
    xyzzy = nil
    xyzzy = xyzzy
    _local_var = :outer
    eval <<-EOF.gsub(/^.*?: /, ""), nil, 'xyzzy'
    1: set_trace_func(lambda{|event, file, line, id, binding, klass|
    2:   events << [event, line, file, klass, id, binding.eval('self'), binding.eval("_local_var")] if file == 'xyzzy'
    3: })
    4: 1.times{|;_local_var| _local_var = :inner
    5:   tap{}
    6: }
    7: class XYZZY
    8:   _local_var = :XYZZY_outer
    9:   def foo
   10:     _local_var = :XYZZY_foo
   11:     bar
   12:   end
   13:   def bar
   14:     _local_var = :XYZZY_bar
   15:     tap{}
   16:   end
   17: end
   18: xyzzy = XYZZY.new
   19: xyzzy.foo
   20: begin; raise RuntimeError; rescue RuntimeError => raised_exc; end
   21: set_trace_func(nil)
    EOF
    self.class.class_eval{remove_const(:XYZZY)}
    return events
  end

  def test_tracepoint
    events1, answer_events = *trace_by_tracepoint(:line, :class, :end, :call, :return, :c_call, :c_return, :raise)

    mesg = events1.map{|e|
      if false
        p [:event, e[0]]
        p [:line_file, e[1], e[2]]
        p [:id, e[4]]
      end
      "#{e[0]} - #{e[2]}:#{e[1]} id: #{e[4]}"
    }.join("\n")
    answer_events.zip(events1){|answer, event|
      assert_equal answer, event, mesg
    }

    events2 = trace_by_set_trace_func
    events1.zip(events2){|ev1, ev2|
      ev2[0] = ev2[0].sub('-', '_').to_sym
      assert_equal ev1[0..2], ev2[0..2], ev1.inspect

      # event, line, file, klass, id, binding.eval('self'), binding.eval("_local_var")
      assert_equal ev1[3].nil?, ev2[3].nil? # klass
      assert_equal ev1[4].nil?, ev2[4].nil? # id
      assert_equal ev1[6], ev2[6]           # _local_var
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
    trace.disable

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
    trace.disable

    assert_raise(RuntimeError){tp_store.lineno}
    assert_raise(RuntimeError){tp_store.event}
    assert_raise(RuntimeError){tp_store.path}
    assert_raise(RuntimeError){tp_store.method_id}
    assert_raise(RuntimeError){tp_store.defined_class}
    assert_raise(RuntimeError){tp_store.binding}
    assert_raise(RuntimeError){tp_store.self}
    assert_raise(RuntimeError){tp_store.return_value}
    assert_raise(RuntimeError){tp_store.raised_exception}
  end

  def foo
  end

  def test_tracepoint_enable
    ary = []
    trace = TracePoint.new(:call){|tp|
      ary << tp.method_id
    }
    foo
    trace.enable{
      foo
    }
    foo
    assert_equal([:foo], ary)

    trace = TracePoint.new{}
    begin
      assert_equal(false, trace.enable)
      assert_equal(true, trace.enable)
      trace.enable{}
      assert_equal(true, trace.enable)
    ensure
      trace.disable
    end
  end

  def test_tracepoint_disable
    ary = []
    trace = TracePoint.trace(:call){|tp|
      ary << tp.method_id
    }
    foo
    trace.disable{
      foo
    }
    foo
    trace.disable
    assert_equal([:foo, :foo], ary)

    trace = TracePoint.new{}
    trace.enable{
      assert_equal(true, trace.disable)
      assert_equal(false, trace.disable)
      trace.disable{}
      assert_equal(false, trace.disable)
    }
  end

  def test_tracepoint_enabled
    trace = TracePoint.trace(:call){|tp|
      #
    }
    assert_equal(true, trace.enabled?)
    trace.disable{
      assert_equal(false, trace.enabled?)
      trace.enable{
        assert_equal(true, trace.enabled?)
      }
    }
    trace.disable
    assert_equal(false, trace.enabled?)
  end

  def method_test_tracepoint_return_value obj
    obj
  end

  def test_tracepoint_return_value
    trace = TracePoint.new(:call, :return){|tp|
      next if tp.path != __FILE__
      case tp.event
      when :call
        assert_raise(RuntimeError) {tp.return_value}
      when :return
        assert_equal("xyzzy", tp.return_value)
      end
    }
    trace.enable{
      method_test_tracepoint_return_value "xyzzy"
    }
  end

  class XYZZYException < Exception; end
  def method_test_tracepoint_raised_exception err
    raise err
  end

  def test_tracepoint_raised_exception
    trace = TracePoint.new(:call, :return){|tp|
      case tp.event
      when :call, :return
        assert_raise(RuntimeError) { tp.raised_exception }
      when :raise
        assert_equal(XYZZYError, tp.raised_exception)
      end
    }
    trace.enable{
      begin
        method_test_tracepoint_raised_exception XYZZYException
      rescue XYZZYException
        # ok
      else
        raise
      end
    }
  end

  def method_for_test_tracepoint_block
    yield
  end

  def test_tracepoint_block
    events = []
    TracePoint.new(:call, :return, :c_call, :b_call, :c_return, :b_return){|tp|
      events << [
        tp.event, tp.method_id, tp.defined_class, tp.self.class,
        /return/ =~ tp.event ? tp.return_value : nil
      ]
    }.enable{
      1.times{
        3
      }
      method_for_test_tracepoint_block{
        4
      }
    }
    # pp events
    # expected_events =
    [[:b_call, :test_tracepoint_block, TestSetTraceFunc, TestSetTraceFunc, nil],
     [:c_call, :times, Integer, Fixnum, nil],
     [:b_call, :test_tracepoint_block, TestSetTraceFunc, TestSetTraceFunc, nil],
     [:b_return, :test_tracepoint_block, TestSetTraceFunc, TestSetTraceFunc, 3],
     [:c_return, :times, Integer, Fixnum, 1],
     [:call, :method_for_test_tracepoint_block, TestSetTraceFunc, TestSetTraceFunc, nil],
     [:b_call, :test_tracepoint_block, TestSetTraceFunc, TestSetTraceFunc, nil],
     [:b_return, :test_tracepoint_block, TestSetTraceFunc, TestSetTraceFunc, 4],
     [:return, :method_for_test_tracepoint_block, TestSetTraceFunc, TestSetTraceFunc, 4],
     [:b_return, :test_tracepoint_block, TestSetTraceFunc, TestSetTraceFunc, 4]
    ].zip(events){|expected, actual|
      assert_equal(expected, actual)
    }
  end

  def test_tracepoint_thread
    events = []
    thread_self = nil
    created_thread = nil
    TracePoint.new(:thread_begin, :thread_end){|tp|
      events << [Thread.current,
                 tp.event,
                 tp.lineno,  #=> 0
                 tp.path,    #=> nil
                 tp.binding, #=> nil
                 tp.defined_class, #=> nil,
                 tp.self.class # tp.self return creating/ending thread
                 ]
    }.enable{
      created_thread = Thread.new{thread_self = self}
      created_thread.join
    }
    assert_equal(self, thread_self)
    assert_equal([created_thread, :thread_begin, 0, nil, nil, nil, Thread], events[0])
    assert_equal([created_thread, :thread_end, 0, nil, nil, nil, Thread], events[1])
    assert_equal(2, events.size)
  end

  def test_tracepoint_inspect
    events = []
    trace = TracePoint.new{|tp| events << [tp.event, tp.inspect]}
    assert_equal("#<TracePoint:disabled>", trace.inspect)
    trace.enable{
      assert_equal("#<TracePoint:enabled>", trace.inspect)
      Thread.new{}.join
    }
    assert_equal("#<TracePoint:disabled>", trace.inspect)
    events.each{|(ev, str)|
      case ev
      when :line
        assert_match(/ in /, str)
      when :call, :c_call
        assert_match(/call \`/, str) # #<TracePoint:c_call `inherited'@../trunk/test.rb:11>
      when :return, :c_return
        assert_match(/return \`/, str) # #<TracePoint:return `m'@../trunk/test.rb:3>
      when /thread/
        assert_match(/\#<Thread:/, str) # #<TracePoint:thread_end of #<Thread:0x87076c0>>
      else
        assert_match(/\#<TracePoint:/, str)
      end
    }
  end

  def test_tracepoint_exception_at_line
    assert_raise(RuntimeError) do
      TracePoint.new(:line) {raise}.enable {
        1
      }
    end
  end

  def test_tracepoint_exception_at_return
    assert_nothing_raised(Timeout::Error, 'infinite trace') do
      assert_normal_exit('def m; end; TracePoint.new(:return) {raise}.enable {m}', '', timeout: 3)
    end
  end

  def test_tracepoint_with_multithreads
    assert_nothing_raised do
      TracePoint.new{
        10.times{
          Thread.pass
        }
      }.enable do
        (1..10).map{
          Thread.new{
            1000.times{
            }
          }
        }.each{|th|
          th.join
        }
      end
    end
  end

  class FOO_ERROR < RuntimeError; end
  class BAR_ERROR < RuntimeError; end
  def m1_test_trace_point_at_return_when_exception
    m2_test_trace_point_at_return_when_exception
  end
  def m2_test_trace_point_at_return_when_exception
    raise BAR_ERROR
  end

  def test_trace_point_at_return_when_exception
    bug_7624 = '[ruby-core:51128] [ruby-trunk - Bug #7624]'
    TracePoint.new{|tp|
      if tp.event == :return &&
        tp.method_id == :m2_test_trace_point_at_return_when_exception
        raise FOO_ERROR
      end
    }.enable do
      assert_raise(FOO_ERROR, bug_7624) do
        m1_test_trace_point_at_return_when_exception
      end
    end

    bug_7668 = '[Bug #7668]'
    ary = []
    trace = TracePoint.new{|tp|
      ary << tp.event
      raise
    }
    begin
      trace.enable{
        1.times{
          raise
        }
      }
    rescue
      assert_equal([:b_call, :b_return], ary, bug_7668)
    end
  end

  def test_trace_point_enable_safe4
    tp = TracePoint.new {}
    func = proc do
      $SAFE = 4
      tp.enable
    end
    assert_security_error_safe4(func)
  end

  def test_trace_point_disable_safe4
    tp = TracePoint.new {}
    func = proc do
      $SAFE = 4
      tp.disable
    end
    assert_security_error_safe4(func)
  end

  def m1_for_test_trace_point_binding_in_ifunc(arg)
    arg + nil
  rescue
  end

  def m2_for_test_trace_point_binding_in_ifunc(arg)
    arg.inject(:+)
  rescue
  end

  def test_trace_point_binding_in_ifunc
    bug7774 = '[ruby-dev:46908]'
    src = %q{
      tp = TracePoint.new(:raise) do |tp|
        tp.binding
      end
      tp.enable do
        obj = Object.new
        class << obj
          include Enumerable
          def each
            yield 1
          end
        end
        %s
      end
    }
    assert_normal_exit src % %q{obj.zip({}) {}}, bug7774
    assert_normal_exit src % %q{
      require 'continuation'
      begin
        c = nil
        obj.sort_by {|x| callcc {|c2| c ||= c2 }; x }
        c.call
      rescue RuntimeError
      end
    }, bug7774

    # TracePoint
    tp_b = nil
    TracePoint.new(:raise) do |tp|
      tp_b = tp.binding
    end.enable do
      m1_for_test_trace_point_binding_in_ifunc(0)
      assert_equal(self, eval('self', tp_b), '[ruby-dev:46960]')

      m2_for_test_trace_point_binding_in_ifunc([0, nil])
      assert_equal(self, eval('self', tp_b), '[ruby-dev:46960]')
    end

    # set_trace_func
    stf_b = nil
    set_trace_func ->(event, file, line, id, binding, klass) do
      stf_b = binding if event == 'raise'
    end
    begin
      m1_for_test_trace_point_binding_in_ifunc(0)
      assert_equal(self, eval('self', stf_b), '[ruby-dev:46960]')

      m2_for_test_trace_point_binding_in_ifunc([0, nil])
      assert_equal(self, eval('self', stf_b), '[ruby-dev:46960]')
    ensure
      set_trace_func(nil)
    end
  end

  def test_tracepoint_b_return_with_next
    n = 0
    TracePoint.new(:b_return){
      n += 1
    }.enable{
      3.times{
        next
      } # 3 times b_retun
    }   # 1 time b_return

    assert_equal 4, n
  end

  def test_const_missing
    bug59398 = '[ruby-core:59398]'
    events = []
    assert !defined?(MISSING_CONSTANT_59398)
    TracePoint.new(:c_call, :c_return, :call, :return){|tp|
      next unless tp.defined_class == Module
      # rake/ext/module.rb aliases :const_missing and Ruby uses the aliased name
      # but this only happens when running the full test suite
      events << [tp.event,tp.method_id] if tp.method_id == :const_missing || tp.method_id == :rake_original_const_missing
    }.enable{
      MISSING_CONSTANT_59398 rescue nil
    }
    if events.map{|e|e[1]}.include?(:rake_original_const_missing)
      assert_equal([
        [:call, :const_missing],
        [:c_call, :rake_original_const_missing],
        [:c_return, :rake_original_const_missing],
        [:return, :const_missing],
      ], events, bug59398)
    else
      assert_equal([
        [:c_call, :const_missing],
        [:c_return, :const_missing]
      ], events, bug59398)
    end
  end

  class AliasedRubyMethod
    def foo; 1; end;
    alias bar foo
  end
  def test_aliased_ruby_method
    events = []
    aliased = AliasedRubyMethod.new
    TracePoint.new(:call, :return){|tp|
      events << [tp.event, tp.method_id]
    }.enable{
      aliased.bar
    }
    assert_equal([
      [:call, :foo],
      [:return, :foo]
    ], events, "should use original method name for tracing ruby methods")
  end
  class AliasedCMethod < Hash
    alias original_size size
    def size; original_size; end
  end

  def test_aliased_c_method
    events = []
    aliased = AliasedCMethod.new
    TracePoint.new(:call, :return, :c_call, :c_return){|tp|
      events << [tp.event, tp.method_id]
    }.enable{
      aliased.size
    }
    assert_equal([
      [:call, :size],
      [:c_call, :original_size],
      [:c_return, :original_size],
      [:return, :size]
    ], events, "should use alias method name for tracing c methods")
  end

  def test_method_missing
    bug59398 = '[ruby-core:59398]'
    events = []
    assert !respond_to?(:missing_method_59398)
    TracePoint.new(:c_call, :c_return, :call, :return){|tp|
      next unless tp.defined_class == BasicObject
      # rake/ext/module.rb aliases :const_missing and Ruby uses the aliased name
      # but this only happens when running the full test suite
      events << [tp.event,tp.method_id] if tp.method_id == :method_missing
    }.enable{
      missing_method_59398 rescue nil
    }
    assert_equal([
      [:c_call, :method_missing],
      [:c_return, :method_missing]
    ], events, bug59398)
  end


  def method_test_rescue_should_not_cause_b_return
    begin
      raise
    rescue
      return
    end
  end

  def method_test_ensure_should_not_cause_b_return
    begin
      raise
    ensure
      return
    end
  end

  def test_rescue_and_ensure_should_not_cause_b_return
    curr_thread = Thread.current
    trace = TracePoint.new(:b_call, :b_return){
      next if curr_thread != Thread.current
      flunk("Should not reach here because there is no block.")
    }

    begin
      trace.enable
      method_test_rescue_should_not_cause_b_return
      begin
        method_test_ensure_should_not_cause_b_return
      rescue
        # ignore
      end
    ensure
      trace.disable
    end
  end

  def method_prefix event
    case event
    when :call, :return
      :n
    when :c_call, :c_return
      :c
    when :b_call, :b_return
      :b
    end
  end

  def method_label tp
    "#{method_prefix(tp.event)}##{tp.method_id}"
  end

  def assert_consistent_call_return message='', check_events: nil
    call_events = []
    return_events = []

    TracePoint.new(*check_events){|tp|
      next unless target_thread?

      case tp.event.to_s
      when /call/
        call_events << method_label(tp)
      when /return/
        return_events << method_label(tp)
      end
    }.enable do
      yield
    end

    assert_equal false, call_events.empty?
    assert_equal false, return_events.empty?
    assert_equal call_events, return_events.reverse, message
  end

  def test_rb_rescue
    events = []
    curr_thread = Thread.current
    TracePoint.new(:b_call, :b_return, :c_call, :c_return){|tp|
      next if curr_thread != Thread.current
      events << [tp.event, tp.method_id]
    }.enable do
      begin
        -Numeric.new
      rescue => e
        # ignore
      end
    end

    assert_equal [
    [:b_call, :test_rb_rescue],
      [:c_call, :new],
        [:c_call, :initialize],
        [:c_return, :initialize],
      [:c_return, :new],
      [:c_call, :-@],
        [:c_call, :coerce],
          [:c_call, :to_s],
          [:c_return, :to_s],
          [:c_call, :new],
            [:c_call, :initialize],
            [:c_return, :initialize],
          [:c_return, :new],
          [:c_call, :exception],
          [:c_return, :exception],
          [:c_call, :backtrace],
          [:c_return, :backtrace],
        [:c_return, :coerce],            # don't miss it!
        [:c_call, :to_s],
        [:c_return, :to_s],
        [:c_call, :to_s],
        [:c_return, :to_s],
        [:c_call, :new],
          [:c_call, :initialize],
          [:c_return, :initialize],
        [:c_return, :new],
        [:c_call, :exception],
        [:c_return, :exception],
        [:c_call, :backtrace],
        [:c_return, :backtrace],
      [:c_return, :-@],
      [:c_call, :===],
      [:c_return, :===],
    [:b_return, :test_rb_rescue]], events
  end

  def test_b_call_with_redo
    assert_consistent_call_return do
      i = 0
      1.times{
        break if (i+=1) > 10
        redo
      }
    end
  end
end
