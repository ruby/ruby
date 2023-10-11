# -*- coding: us-ascii -*-
# frozen_string_literal: false
require 'test/unit'
require "rbconfig/sizeof"
require "timeout"
require "fiddle"

class TestThread < Test::Unit::TestCase
  class Thread < ::Thread
    Threads = []
    def self.new(*)
      th = super
      Threads << th
      th
    end
  end

  def setup
    STDERR.puts "\n\n!!! setup #{self.instance_variable_get(:@__name__)}"

    Thread::Threads.clear
  end

  def teardown
    STDERR.puts "\n\n!!! teardown #{self.instance_variable_get(:@__name__)}"

    Thread::Threads.each do |t|
      t.kill if t.alive?
      begin
        t.join
      rescue Exception
      end
    end
  end

=begin
  def test_thread_local
    t = Thread.new { sleep }

    assert_equal(false, t.key?(:foo))

    t["foo"] = "foo"
    t["bar"] = "bar"
    t["baz"] = "baz"

    assert_equal(true, t.key?(:foo))
    assert_equal(true, t.key?("foo"))
    assert_equal(false, t.key?(:qux))
    assert_equal(false, t.key?("qux"))

    assert_equal([:foo, :bar, :baz].sort, t.keys.sort)

  ensure
    t&.kill&.join
  end

  def test_mutex_fifo_like_lock
    m1 = Thread::Mutex.new
    m2 = Thread::Mutex.new
    m1.lock
    m2.lock
    m1.unlock
    m2.unlock
    assert_equal(false, m1.locked?)
    assert_equal(false, m2.locked?)

    m3 = Thread::Mutex.new
    m1.lock
    m2.lock
    m3.lock
    m1.unlock
    m2.unlock
    m3.unlock
    assert_equal(false, m1.locked?)
    assert_equal(false, m2.locked?)
    assert_equal(false, m3.locked?)
  end

  def test_recursive_outer
    arr = []
    obj = Struct.new(:foo, :visited).new(arr, false)
    arr << obj
    def obj.hash
      self[:visited] = true
      super
      raise "recursive_outer should short circuit intermediate calls"
    end
    assert_nothing_raised {arr.hash}
    assert(obj[:visited], "obj.hash was not called")
  end

  def invoke_rec script, vm_stack_size, machine_stack_size, use_length = true
    env = {}
    env['RUBY_THREAD_VM_STACK_SIZE'] = vm_stack_size.to_s if vm_stack_size
    env['RUBY_THREAD_MACHINE_STACK_SIZE'] = machine_stack_size.to_s if machine_stack_size
    out, err, status = EnvUtil.invoke_ruby([env, '-e', script], '', true, true)
    assert_not_predicate(status, :signaled?, err)

    use_length ? out.length : out
  end

  def test_stack_size
    h_default = eval(invoke_rec('p RubyVM::DEFAULT_PARAMS', nil, nil, false))
    h_0 = eval(invoke_rec('p RubyVM::DEFAULT_PARAMS', 0, 0, false))
    h_large = eval(invoke_rec('p RubyVM::DEFAULT_PARAMS', 1024 * 1024 * 10, 1024 * 1024 * 10, false))

    assert_operator(h_default[:thread_vm_stack_size], :>, h_0[:thread_vm_stack_size],
                    "0 thread_vm_stack_size")
    assert_operator(h_default[:thread_vm_stack_size], :<, h_large[:thread_vm_stack_size],
                    "large thread_vm_stack_size")
    assert_operator(h_default[:thread_machine_stack_size], :>=, h_0[:thread_machine_stack_size],
                    "0 thread_machine_stack_size")
    assert_operator(h_default[:thread_machine_stack_size], :<=, h_large[:thread_machine_stack_size],
                    "large thread_machine_stack_size")
    assert_equal("ok", invoke_rec('print :ok', 1024 * 1024 * 100, nil, false))
  end

  def test_vm_machine_stack_size
    script = 'def rec; print "."; STDOUT.flush; rec; end; rec'
    size_default = invoke_rec script, nil, nil
    assert_operator(size_default, :>, 0, "default size")
    size_0 = invoke_rec script, 0, nil
    assert_operator(size_default, :>, size_0, "0 size")
    size_large = invoke_rec script, 1024 * 1024 * 10, nil
    assert_operator(size_default, :<, size_large, "large size")
  end

  def test_machine_stack_size
    # check machine stack size
    # Note that machine stack size may not change size (depend on OSs)
    script = 'def rec; print "."; STDOUT.flush; 1.times{1.times{1.times{rec}}}; end; Thread.new{rec}.join'
    vm_stack_size = 1024 * 1024
    size_default = invoke_rec script, vm_stack_size, nil
    size_0 = invoke_rec script, vm_stack_size, 0
    assert_operator(size_default, :>=, size_0, "0 size")
    size_large = invoke_rec script, vm_stack_size, 1024 * 1024 * 10
    assert_operator(size_default, :<=, size_large, "large size")
  end unless /mswin|mingw/ =~ RUBY_PLATFORM

  def test_subclass_no_initialize
    t = Module.new do
      break eval("class C\u{30b9 30ec 30c3 30c9} < Thread; self; end")
    end
    t.class_eval do
      def initialize
      end
    end
    assert_raise_with_message(ThreadError, /C\u{30b9 30ec 30c3 30c9}/) do
      t.new {}
    end
  end
=end

  def test_thread_interrupt_for_killed_thread
    opts = { timeout: 5, timeout_error: nil }

    # prevent SIGABRT from slow shutdown with RJIT
    opts[:reprieve] = 3 if defined?(RubyVM::RJIT) && RubyVM::RJIT.enabled?

    assert_normal_exit(<<-_end, '[Bug #8996]', **opts)
      Thread.report_on_exception = false
      trap(:TERM){exit}
      while true
        t = Thread.new{sleep 0}
        t.raise Interrupt
        Thread.pass # allow t to finish
        n = Thread.list.size
        raise "#{n} > 1000" if n > 1000
      end
    _end
  end
end
