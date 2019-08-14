# frozen_string_literal: false
require 'test/unit'
require 'optparse'
require 'optparse/kwargs'

class TestOptionParser < Test::Unit::TestCase
end
class TestOptionParser::KwArg < Test::Unit::TestCase
  class K
    def initialize(host:, port: 8080)
      @host = host
      @port = port
    end
  end

  class DummyOutput < String
    alias write concat
  end
  def assert_no_error(*args)
    $stderr, stderr = DummyOutput.new, $stderr
    assert_nothing_raised(*args) {return yield}
  ensure
    stderr, $stderr = $stderr, stderr
    $!.backtrace.delete_if {|e| /\A#{Regexp.quote(__FILE__)}:#{__LINE__-2}/o =~ e} if $!
    assert_empty(stderr)
  end
  alias no_error assert_no_error

  def test_kwarg
    opt = OptionParser.new
    options = opt.define_by_keywords({}, K.instance_method(:initialize),
                                     port: [Integer])
    assert_raise(OptionParser::MissingArgument) {opt.parse!(%w"--host")}
    assert_nothing_raised {opt.parse!(%w"--host=localhost")}
    assert_equal("localhost", options[:host])
    assert_nothing_raised {opt.parse!(%w"--port")}
    assert_nothing_raised {opt.parse!(%w"--port=80")}
    assert_equal(80, options[:port])
  end
end
