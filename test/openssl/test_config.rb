require 'openssl'
require "test/unit"

class OpenSSL::TestConfig < Test::Unit::TestCase
  def test_freeze
    c = OpenSSL::Config.new
    c['foo'] = [['key', 'value']]
    c.freeze

    # [ruby-core:18377]
    assert_raise(RuntimeError, /frozen/) do
      c['foo'] = [['key', 'wrong']]
    end
  end
end
