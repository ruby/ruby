# frozen_string_literal: true

require_relative "helper"
require "rubygems"
require "shellwords"

class TestGemConfig < Gem::TestCase
  def test_good_rake_path_is_escaped
    path = Gem::TestCase.class_variable_get(:@@good_rake)
    ruby, rake = path.shellsplit
    assert_equal(Gem.ruby, ruby)
    assert_match(%r{/good_rake.rb\z}, rake)
  end

  def test_bad_rake_path_is_escaped
    path = Gem::TestCase.class_variable_get(:@@bad_rake)
    ruby, rake = path.shellsplit
    assert_equal(Gem.ruby, ruby)
    assert_match(%r{/bad_rake.rb\z}, rake)
  end
end
