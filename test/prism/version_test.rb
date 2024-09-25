# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class VersionTest < TestCase
    def test_prism_version_is_set
      refute_nil VERSION
    end
  end
end
