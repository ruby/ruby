require 'test/unit'
require 'yaml'

module Syck
  class TestArray < Test::Unit::TestCase
    def setup
      @list = [{ :a => 'b' }, 'foo']
    end

    def test_to_yaml
      assert_equal @list, YAML.load(@list.to_yaml)
    end

    def test_dump
      assert_equal @list, YAML.load(YAML.dump(@list))
    end
  end
end
