require 'test/unit'
require 'drb'
require 'drb/timeridconv'
require 'drb/weakidconv'

module DRbObjectTest
  class Foo
    def initialize
      @foo = 'foo'
    end
  end

  def teardown
    DRb.stop_service
  end

  def drb_eq(obj)
    proxy = DRbObject.new(obj)
    assert_equal(obj, DRb.to_obj(proxy.__drbref))
  end

  def test_DRbObject_id_dereference
    drb_eq(Foo.new)
    drb_eq(Foo)
    drb_eq(File)
    drb_eq(Enumerable)
    drb_eq(nil)
    drb_eq(1)
    drb_eq($stdout)
    drb_eq([])
  end
end

class TestDRbObject < Test::Unit::TestCase
  include DRbObjectTest

  def setup
    DRb.start_service
  end
end

class TestDRbObjectTimerIdConv < Test::Unit::TestCase
  include DRbObjectTest

  def setup
    DRb.start_service(nil, nil, {:idconv => DRb::TimerIdConv.new})
  end
end

class TestDRbObjectWeakIdConv < Test::Unit::TestCase
  include DRbObjectTest

  def setup
    DRb.start_service(nil, nil, {:idconv => DRb::WeakIdConv.new})
  end
end
