require 'openssl'
require "test/unit"

class OpenSSL::TestConfig < Test::Unit::TestCase
  def test_freeze
    c = OpenSSL::Config.new
    c['foo'] = [['key', 'value']]
    c.freeze

    # [ruby-core:18377]
    # RuntimeError for 1.9, TypeError for 1.8
    assert_raise(TypeError, /frozen/) do
      c['foo'] = [['key', 'wrong']]
    end
  end
end
