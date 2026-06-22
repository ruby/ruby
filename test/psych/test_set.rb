# encoding: UTF-8
# frozen_string_literal: true
require_relative 'helper'
require 'set' unless defined?(Set)

module Psych
  class TestSet < TestCase
    def setup
      @set = ::Set.new([1, 2, 3])
    end

    def test_dump
      assert_equal <<~YAML, Psych.dump(@set)
        --- !ruby/object:Set
        hash:
          1: true
          2: true
          3: true
      YAML
    end

    def test_load
      assert_equal @set, Psych.load(<<~YAML, permitted_classes: [::Set])
        --- !ruby/object:Set
        hash:
          1: true
          2: true
          3: true
      YAML
    end

    def test_roundtrip
      assert_equal @set, Psych.load(Psych.dump(@set), permitted_classes: [::Set])
    end
  end
end
