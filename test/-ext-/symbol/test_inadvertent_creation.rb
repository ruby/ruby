require 'test/unit'
require "-test-/symbol/symbol"

module Test_Symbol
  class TestInadvertent < Test::Unit::TestCase
    def self.noninterned_name
      th = Thread.current.object_id.to_s(36)
      begin
        name = "#{th}.#{rand(0x1000).to_s(16)}.#{Time.now.usec}"
      end while Bug::Symbol.interned?(name)
      name
    end

    def setup
      @obj = Object.new
    end

    Feature5112 = '[ruby-core:38576]'

    def test_public_send
      name = self.class.noninterned_name
      e = assert_raise(NoMethodError) {@obj.public_send(name, Feature5112)}
      assert_not_send([Bug::Symbol, :interned?, name])
      assert_equal(name, e.name)
      assert_equal([Feature5112], e.args)
    end

    def test_send
      name = self.class.noninterned_name
      e = assert_raise(NoMethodError) {@obj.send(name, Feature5112)}
      assert_not_send([Bug::Symbol, :interned?, name])
      assert_equal(name, e.name)
      assert_equal([Feature5112], e.args)
    end

    def test___send__
      name = self.class.noninterned_name
      e = assert_raise(NoMethodError) {@obj.__send__(name, Feature5112)}
      assert_not_send([Bug::Symbol, :interned?, name])
      assert_equal(name, e.name)
      assert_equal([Feature5112], e.args)
    end
  end
end
