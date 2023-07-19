# frozen_string_literal: true
require_relative "helper"
require "rubygems"
require "shellwords"

class TestGemConfig < Gem::TestCase
  def test_datadir
    util_make_gems
    spec = Gem::Specification.find_by_name("a")
    spec.activate
    assert_equal "#{spec.full_gem_path}/data/a", spec.datadir
  end

  def test_good_rake_path_is_escaped
    path = Gem::TestCase.class_variable_get(:@@good_rake)
    ruby, rake = path.shellsplit
    assert_equal(Gem.ruby, ruby)
    assert_match(/\/good_rake.rb\z/, rake)
  end

  def test_bad_rake_path_is_escaped
    path = Gem::TestCase.class_variable_get(:@@bad_rake)
    ruby, rake = path.shellsplit
    assert_equal(Gem.ruby, ruby)
    assert_match(/\/bad_rake.rb\z/, rake)
  end
end
