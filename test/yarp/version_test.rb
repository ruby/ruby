# frozen_string_literal: true

require_relative "test_helper"

module YARP
  class VersionTest < TestCase
    def test_version_is_set
      refute_nil VERSION
    end
  end
end
