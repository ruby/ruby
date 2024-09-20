# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class NewlineOffsetsTest < TestCase
    Fixture.each do |fixture|
      define_method(fixture.test_name) { assert_newline_offsets(fixture) }
    end

    private

    def assert_newline_offsets(fixture)
      source = fixture.read

      expected = [0]
      source.b.scan("\n") { expected << $~.offset(0)[0] + 1 }

      assert_equal expected, Prism.parse(source).source.offsets
    end
  end
end
