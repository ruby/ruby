require 'openssl'
require "test/unit"

class OpenSSL::TestConfig < Test::Unit::TestCase
  def test_freeze
    skip "need an argument for OpenSSL::Config.new on Windows" if /mswin|mingw/ =~ RUBY_PLATFORM
    c = OpenSSL::Config.new
    c['foo'] = [['key', 'value']]
    c.freeze

    # [ruby-core:18377]
    assert_raise(RuntimeError, /frozen/) do
      c['foo'] = [['key', 'wrong']]
    end
  end
end
