require 'test/unit'
require 'yaml'

module Syck
  class TestClass < Test::Unit::TestCase
    def test_to_yaml
      assert_raises(::TypeError) do
        TestClass.to_yaml
      end
    end

    def test_dump
      assert_raises(::TypeError) do
        YAML.dump TestClass
      end
    end
  end
end
