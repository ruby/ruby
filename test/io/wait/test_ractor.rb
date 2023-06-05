# frozen_string_literal: true
require 'test/unit'
require 'rbconfig'

class TestIOWaitInRactor < Test::Unit::TestCase
  def test_ractor
    ext = "/io/wait.#{RbConfig::CONFIG['DLEXT']}"
    path = $".find {|path| path.end_with?(ext)}
    assert_in_out_err(%W[-r#{path}], <<-"end;", ["true"], [])
      $VERBOSE = nil
      r = Ractor.new do
        $stdout.equal?($stdout.wait_writable)
      end
      puts r.take
    end;
  end
end if defined? Ractor
