require 'psych/helper'

module Psych
  class TestString < TestCase
    def test_binary_string_null
      string = "\x00"
      yml = Psych.dump string
      assert_match(/binary/, yml)
      assert_equal string, Psych.load(yml)
    end

    def test_binary_string
      string = binary_string
      yml = Psych.dump string
      assert_match(/binary/, yml)
      assert_equal string, Psych.load(yml)
    end

    def test_non_binary_string
      string = binary_string(0.29)
      yml = Psych.dump string
      refute_match(/binary/, yml)
      assert_equal string, Psych.load(yml)
    end

    def test_string_with_ivars
      food = "is delicious"
      ivar = "on rock and roll"
      food.instance_variable_set(:@we_built_this_city, ivar)

      str = Psych.load Psych.dump food
      assert_equal ivar, food.instance_variable_get(:@we_built_this_city)
    end

    def test_binary
      string = [0, 123,22, 44, 9, 32, 34, 39].pack('C*')
      assert_cycle string
    end

    def binary_string percentage = 0.31, length = 100
      string = ''
      (percentage * length).to_i.times do |i|
        string << "\b"
      end
      string << 'a' * (length - string.length)
      string
    end
  end
end
