# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems'

class TestConfig < Gem::TestCase

  def test_datadir
    util_make_gems
    spec = Gem::Specification.find_by_name("a")
    spec.activate
    assert_equal "#{spec.full_gem_path}/data/a", spec.datadir
  end

  def test_good_rake_path_is_escaped
    path = Gem::TestCase.class_eval('@@good_rake')
    assert_match(/#{Gem.ruby} "[^"]*good_rake.rb"/, path)
  end

  def test_bad_rake_path_is_escaped
    path = Gem::TestCase.class_eval('@@bad_rake')
    assert_match(/#{Gem.ruby} "[^"]*bad_rake.rb"/, path)
  end

end
