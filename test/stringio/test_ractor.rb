# frozen_string_literal: true
require 'test/unit'

class TestStringIOInRactor < Test::Unit::TestCase
  def setup
    omit unless defined? Ractor
  end

  def test_ractor
    assert_in_out_err([], <<-"end;", ["true"], [])
      require "stringio"
      $VERBOSE = nil
      r = Ractor.new do
        io = StringIO.new(+"")
        io.puts "abc"
        io.truncate(0)
        io.puts "def"
        "\0\0\0\0def\n" == io.string
      end
      puts r.take
    end;
  end
end
