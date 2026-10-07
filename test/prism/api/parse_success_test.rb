# frozen_string_literal: true

require_relative "../test_helper"

module Ruby::Prism
  class ParseSuccessTest < TestCase
    def test_parse_success?
      assert Ruby::Prism.parse_success?("1")
      refute Ruby::Prism.parse_success?("<>")
    end

    def test_parse_file_success?
      assert Ruby::Prism.parse_file_success?(__FILE__)
    end
  end
end
