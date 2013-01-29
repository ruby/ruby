require 'test/unit'
require '-test-/debug'

class TestDebug < Test::Unit::TestCase

  def binds_check binds
    count = Hash.new(0)
    assert_instance_of(Array, binds)
    binds.each{|(_self, bind, klass, iseq, loc)|
      if _self == self
        count[:self] += 1
      end

      if bind
        assert_instance_of(Binding, bind)
        count[:bind] += 1
      end

      if klass
        assert(klass.instance_of?(Module) || klass.instance_of?(Class))
        count[:class] += 1
      end

      if iseq
        count[:iseq] += 1
        assert_instance_of(RubyVM::InstructionSequence, iseq)

        # check same location
        assert_equal(loc.path, iseq.path)
        assert_equal(loc.absolute_path, iseq.absolute_path)
        assert_equal(loc.label, iseq.label)
        assert_operator(loc.lineno, :>=, iseq.first_lineno)
      end

      assert_instance_of(Thread::Backtrace::Location, loc)

    }
    assert_operator(0, :<, count[:self])
    assert_operator(0, :<, count[:bind])
    assert_operator(0, :<, count[:iseq])
    assert_operator(0, :<, count[:class])
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
    binds_check binds
  end
end
