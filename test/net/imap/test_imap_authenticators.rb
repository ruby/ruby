# frozen_string_literal: true

require "net/imap"
require "test/unit"

class IMAPAuthenticatorsTest < Test::Unit::TestCase

  PLAIN = Net::IMAP::PlainAuthenticator

  def test_plain
    assert_equal("\0authc\0passwd",
                 PLAIN.new("authc", "passwd").process(nil))
    assert_equal("authz\0user\0pass",
                 PLAIN.new("user", "pass", authzid: "authz").process(nil))
  end

  def test_plain_no_null_chars
    assert_raise(ArgumentError) { PLAIN.new("bad\0user", "pass") }
    assert_raise(ArgumentError) { PLAIN.new("user", "bad\0pass") }
    assert_raise(ArgumentError) { PLAIN.new("u", "p", authzid: "bad\0authz") }
  end

end
