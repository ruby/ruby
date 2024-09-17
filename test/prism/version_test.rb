# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class VersionTest < TestCase
    def test_prism_version_is_set
      refute_nil VERSION
    end

    def test_syntax_versions
      assert Prism.parse("1 + 1", version: "3.3.0").success?
      assert Prism.parse("1 + 1", version: "3.3.1").success?
      assert Prism.parse("1 + 1", version: "3.3.9").success?
      assert Prism.parse("1 + 1", version: "3.3.10").success?

      assert Prism.parse("1 + 1", version: "3.4.0").success?
      assert Prism.parse("1 + 1", version: "3.4.9").success?
      assert Prism.parse("1 + 1", version: "3.4.10").success?

      assert Prism.parse("1 + 1", version: "latest").success?

      # Test edge case
      error = assert_raise ArgumentError do
        Prism.parse("1 + 1", version: "latest2")
      end
      assert_equal "invalid version: latest2", error.message

      assert_raise ArgumentError do
        Prism.parse("1 + 1", version: "3.3.a")
      end

      # Not supported version syntax
      assert_raise ArgumentError do
        Prism.parse("1 + 1", version: "3.3")
      end

      # Not supported version (too old)
      assert_raise ArgumentError do
        Prism.parse("1 + 1", version: "3.2.0")
      end

      # Not supported version (too new)
      assert_raise ArgumentError do
        Prism.parse("1 + 1", version: "3.5.0")
      end
    end
  end
end
