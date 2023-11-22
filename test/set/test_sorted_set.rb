# frozen_string_literal: false
require 'test/unit'
require 'set'

class TC_SortedSet < Test::Unit::TestCase
  def base_dir
    "#{__dir__}/../lib"
  end

  def assert_runs(ruby, options: nil)
    options = ['-I', base_dir, *options]
    r = system(RbConfig.ruby, *options, '-e', ruby)
    assert(r)
  end

  def test_error
    assert_runs <<~RUBY
      require "set"

      r = begin
        puts SortedSet.new
      rescue Exception => e
        e.message
      end
      raise r unless r.match?(/has been extracted/)
    RUBY
  end

  def test_ok_with_gem
    assert_runs <<~RUBY, options: ['-I', "#{__dir__}/fixtures/fake_sorted_set_gem"]
      require "set"

      var = SortedSet.new.to_s
    RUBY
  end

  def test_ok_require
    assert_runs <<~RUBY, options: ['-I', "#{__dir__}/fixtures/fake_sorted_set_gem"]
      require "set"
      require "sorted_set"

      var = SortedSet.new.to_s
    RUBY
  end
end
