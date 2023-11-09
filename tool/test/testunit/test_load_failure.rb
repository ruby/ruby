# frozen_string_literal: true
require 'test/unit'

class TestLoadFailure < Test::Unit::TestCase
  def test_load_failure
    assert_not_predicate(load_failure, :success?)
  end

  def test_load_failure_parallel
    assert_not_predicate(load_failure("-j2"), :success?)
  end

  private

  def load_failure(*args)
    IO.popen([*@__runner_options__[:ruby], "#{__dir__}/../runner.rb",
              "#{__dir__}/test4test_load_failure.rb",
              "--verbose", *args], err: [:child, :out]) {|f|
      assert_include(f.read, "test4test_load_failure.rb")
    }
    $?
  end
end
