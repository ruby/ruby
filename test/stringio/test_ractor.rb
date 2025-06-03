# frozen_string_literal: true
require 'test/unit'

class TestStringIOInRactor < Test::Unit::TestCase
  def setup
    omit unless defined? Ractor
  end

  def test_ractor
    assert_in_out_err([], <<-"end;", ["true"], [])
      class Ractor
        alias value take unless method_defined? :value # compat with Ruby 3.4 and olders
      end

      require "stringio"
      $VERBOSE = nil
      r = Ractor.new do
        io = StringIO.new(+"")
        io.puts "abc"
        io.truncate(0)
        io.puts "def"
        "\0\0\0\0def\n" == io.string
      end
      puts r.value
    end;
  end
end
