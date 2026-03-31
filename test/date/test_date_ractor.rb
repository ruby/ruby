# frozen_string_literal: true
require 'test/unit'
require 'date'

class TestDateParseRactor < Test::Unit::TestCase
  def code(klass = Date, share: false)
    <<~RUBY.gsub('Date', klass.name)
      share = #{share}
      d = Date.parse('Aug 23:55')
      Ractor.make_shareable(d) if share
      d2, d3 = Ractor.new(d) { |d| [d, Date.parse(d.to_s)] }.value
      if share
        assert_same d, d2
      else
        assert_equal d, d2
      end
      assert_equal d, d3
    RUBY
  end

  def test_date_ractor
    assert_ractor(code                       , require: 'date')
    assert_ractor(code(          share: true), require: 'date')
    assert_ractor(code(DateTime             ), require: 'date')
    assert_ractor(code(DateTime, share: true), require: 'date')
  end
end
