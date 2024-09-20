# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class ParseSuccessTest < TestCase
    def test_parse_success?
      assert Prism.parse_success?("1")
      refute Prism.parse_success?("<>")
    end

    def test_parse_file_success?
      assert Prism.parse_file_success?(__FILE__)
    end
  end
end
