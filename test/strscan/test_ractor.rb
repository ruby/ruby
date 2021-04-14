# frozen_string_literal: true
require 'test/unit'

class TestStringScannerRactor < Test::Unit::TestCase
  def setup
    pend unless defined? Ractor
  end

  def test_ractor
    assert_in_out_err([], <<-"end;", ["stra", " ", "strb", " ", "strc"], [])
      require "strscan"
      $VERBOSE = nil
      r = Ractor.new do
        s = StringScanner.new("stra strb strc", true)
        [
          s.scan(/\\w+/),
          s.scan(/\\s+/),
          s.scan(/\\w+/),
          s.scan(/\\s+/),
          s.scan(/\\w+/),
          s.scan(/\\w+/),
          s.scan(/\\w+/)
        ]
      end
      puts r.take.compact
    end;
  end
end
