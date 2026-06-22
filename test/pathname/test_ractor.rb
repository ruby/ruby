# frozen_string_literal: true
require "test/unit"
require "pathname"

class TestPathnameRactor < Test::Unit::TestCase
  def setup
    omit unless defined? Ractor
  end

  def test_ractor_shareable
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    class Ractor
      alias value take
    end unless Ractor.method_defined? :value # compat with Ruby 3.4 and olders

    begin;
      $VERBOSE = nil
      require "pathname"
      r = Ractor.new Pathname("a") do |x|
        x.join(Pathname("b"), Pathname("c"))
      end
      assert_equal(Pathname("a/b/c"), r.value)

      r = Ractor.new Pathname("a") do |a|
        Pathname("b").relative_path_from(a)
      end
      assert_equal(Pathname("../b"), r.value)
    end;
  end
end
