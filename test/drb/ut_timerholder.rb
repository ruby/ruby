# frozen_string_literal: false
require 'test/unit'
require 'drb/timeridconv'

module DRbTests

class TimerIdConvTest < Test::Unit::TestCase
  def test_usecase_01
    keeping = 0.1
    idconv = DRb::TimerIdConv.new(keeping)

    key = idconv.to_id(self)
    assert_equal(key, self.__id__)
    sleep(keeping)

    assert_equal(idconv.to_id(false), false.__id__)
    assert_equal(idconv.to_obj(key), self)
    sleep(keeping)

    assert_equal(idconv.to_obj(key), self)
    sleep(keeping)

    assert_equal(idconv.to_id(true), true.__id__)
    sleep(keeping)

    assert_raise do
      assert_equal(idconv.to_obj(key))
    end

    assert_raise do
      assert_equal(idconv.to_obj(false.__id__))
    end
  end
end


end

