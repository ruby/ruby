# frozen_string_literal: true
require_relative 'helper'

module Psych
  class TestStringIO < TestCase
    # The superclass of StringIO before Ruby 3.0 was `Data`,
    # which can interfere with the Ruby 3.2+ `Data` dumping.
    def test_stringio
      assert_nothing_raised do
        Psych.dump(StringIO.new("foo"))
      end
    end
  end
end
