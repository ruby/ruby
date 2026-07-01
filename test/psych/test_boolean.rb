# frozen_string_literal: true
require_relative 'helper'

module Psych
  ###
  # Test booleans from YAML spec:
  # http://yaml.org/type/bool.html
  class TestBoolean < TestCase
    # true/false are booleans in both YAML 1.1 and 1.2.
    %w{ true True TRUE }.each do |truth|
      define_method(:"test_#{truth}") do
        assert_equal true, Psych.load("--- #{truth}")
      end
    end

    %w{ false False FALSE }.each do |truth|
      define_method(:"test_#{truth}") do
        assert_equal false, Psych.load("--- #{truth}")
      end
    end

    # yes/on and no/off are booleans only under YAML 1.1 (the libyaml backend).
    # The YAML 1.2 libfyaml backend keeps them as plain strings.
    %w{ yes Yes YES on On ON }.each do |truth|
      define_method(:"test_#{truth}") do
        assert_equal(libfyaml? ? truth : true, Psych.load("--- #{truth}"))
      end
    end

    %w{ no No NO off Off OFF }.each do |truth|
      define_method(:"test_#{truth}") do
        assert_equal(libfyaml? ? truth : false, Psych.load("--- #{truth}"))
      end
    end

    ###
    # YAML spec says "y" and "Y" may be used as true, but Syck treats them
    # as literal strings
    def test_y
      assert_equal "y", Psych.load("--- y")
      assert_equal "Y", Psych.load("--- Y")
    end

    ###
    # YAML spec says "n" and "N" may be used as false, but Syck treats them
    # as literal strings
    def test_n
      assert_equal "n", Psych.load("--- n")
      assert_equal "N", Psych.load("--- N")
    end
  end
end
