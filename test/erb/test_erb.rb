require 'test/unit'
require 'erb'

class TestERB < Test::Unit::TestCase
  class MyError < RuntimeError ; end

  def test_without_filename
    erb = ERB.new("<% raise ::TestERB::MyError %>")
    e = assert_raise(MyError) {
      erb.result
    }
    assert_equal("(erb):1", e.backtrace[0])
  end

  def test_with_filename
    erb = ERB.new("<% raise ::TestERB::MyError %>")
    erb.filename = "test filename"
    e = assert_raise(MyError) {
      erb.result
    }
    assert_equal("test filename:1", e.backtrace[0])
  end

  def test_without_filename_with_safe_level
    erb = ERB.new("<% raise ::TestERB::MyError %>", 1)
    e = assert_raise(MyError) {
      erb.result
    }
    assert_equal("(erb):1", e.backtrace[0])
  end

  def test_with_filename_and_safe_level
    erb = ERB.new("<% raise ::TestERB::MyError %>", 1)
    erb.filename = "test filename"
    e = assert_raise(MyError) {
      erb.result
    }
    assert_equal("test filename:1", e.backtrace[0])
  end
end
