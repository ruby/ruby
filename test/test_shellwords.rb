require 'test/unit'
require 'shellwords'

class TestShellwords < Test::Unit::TestCase

  include Shellwords

  def setup
    @not_string = Class.new
    @cmd = "ruby my_prog.rb | less"
  end


  def test_string
    assert_instance_of(Array, shellwords(@cmd))
    assert_equal(4, shellwords(@cmd).length)
  end

  def test_unmatched_double_quote
    bad_cmd = 'one two "three'
    assert_raise ArgumentError do
      shellwords(bad_cmd)
    end
  end

  def test_unmatched_single_quote
    bad_cmd = "one two 'three"
    assert_raise ArgumentError do
      shellwords(bad_cmd)
    end
  end

  def test_unmatched_quotes
    bad_cmd = "one '"'"''""'""
    assert_raise ArgumentError do
      shellwords(bad_cmd)
    end
  end
end
