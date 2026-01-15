# frozen_string_literal: false
require 'test/unit'
require '-test-/debug'

class TestDebug < Test::Unit::TestCase

  def binds_check(binds, msg = nil)
    count = Hash.new(0)
    assert_instance_of(Array, binds, msg)
    binds.each{|(_self, bind, klass, iseq, loc)|
      if _self == self
        count[:self] += 1
      end

      if bind
        assert_instance_of(Binding, bind, msg)
        count[:bind] += 1
      end

      if klass
        assert(klass.instance_of?(Module) || klass.instance_of?(Class), msg)
        count[:class] += 1
      end

      if iseq
        count[:iseq] += 1
        assert_instance_of(RubyVM::InstructionSequence, iseq, msg)

        # Backtraces and source locations don't match for :c_trace methods
        unless iseq.disasm.include?('C_TRACE')
          # check same location
          assert_equal(loc.path, iseq.path, msg)
          assert_equal(loc.absolute_path, iseq.absolute_path, msg)
          #assert_equal(loc.label, iseq.label, msg)
          assert_operator(loc.lineno, :>=, iseq.first_lineno, msg)
        end
      end

      assert_instance_of(Thread::Backtrace::Location, loc, msg)

    }
    assert_operator(0, :<, count[:self], msg)
    assert_operator(0, :<, count[:bind], msg)
    assert_operator(0, :<, count[:iseq], msg)
    assert_operator(0, :<, count[:class], msg)
  end

  def test_inspector_open
    binds = Bug::Debug.inspector
    binds_check binds
  end

  def inspector_in_eval
    eval("Bug::Debug.inspector")
  end

  def test_inspector_open_in_eval
    bug7635 = '[ruby-core:51640]'
    binds = inspector_in_eval
    binds_check binds, bug7635
  end

  class MyRelation
    include Enumerable

    def each
      yield :each_entry
    end
  end

  def test_lazy_block
    x = MyRelation.new.any? do
      Bug::Debug.inspector
      true
    end
    assert_equal true, x, '[Bug #15105]'
  end
end

# This is a YJIT test, but we can't test this without a C extension that calls
# rb_debug_inspector_open(), so we're testing it using "-test-/debug" here.
class TestDebugWithYJIT < Test::Unit::TestCase
  class LocalSetArray
    def to_a
      Bug::Debug.inspector.each do |_, binding,|
        binding.local_variable_set(:local, :ok) if binding
      end
      [:ok]
    end
  end

  class DebugArray
    def to_a
      Bug::Debug.inspector
      [:ok]
    end
  end

  def test_yjit_invalidates_getlocal_after_splatarray
    val = getlocal_after_splatarray(LocalSetArray.new)
    assert_equal [:ok, :ok], val
  end

  def test_yjit_invalidates_setlocal_after_splatarray
    val = setlocal_after_splatarray(DebugArray.new)
    assert_equal [:ok], val
  end

  def test_yjit_invalidates_setlocal_after_proc_call
    val = setlocal_after_proc_call(proc { Bug::Debug.inspector; :ok })
    assert_equal :ok, val
  end

  private

  def getlocal_after_splatarray(array)
    local = 1
    [*array, local]
  end

  def setlocal_after_splatarray(array)
    local = *array # setlocal followed by splatarray
    itself # split a block using a C call
    local # getlocal
  end

  def setlocal_after_proc_call(block)
    local = block.call # setlocal followed by OPTIMIZED_METHOD_TYPE_CALL
    itself # split a block using a C call
    local # getlocal
  end
end if defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
