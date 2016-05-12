# frozen_string_literal: false
require 'test/unit'
require '-test-/exception'

module Bug
  class TestException < Test::Unit::TestCase
    def test_enc_raise
      feature5650 = '[ruby-core:41160]'
      Encoding.list.each do |enc|
        next unless enc.ascii_compatible?
        e = assert_raise(Bug::Exception) {Bug::Exception.enc_raise(enc, "[Feature #5650]")}
        assert_equal(enc, e.message.encoding, feature5650)
      end
    end
  end
end
