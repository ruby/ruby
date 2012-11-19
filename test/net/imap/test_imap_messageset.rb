require 'net/imap'
require 'test/unit'


class IMAPTestStub
  def initialize
    @strings = []
  end
  def put_string(s)
    @strings << s
  end
  attr_accessor :strings
end

class IMAPMessageSetTest < Test::Unit::TestCase
  
  ### Validation Tests

  def assert_messageset_ok_with(set)
    ms = Net::IMAP::MessageSet.new(set)
    assert_nothing_raised do
      ms.validate
    end
  end
  
  def test_allows_integer
    assert_messageset_ok_with 1
  end
  def test_allows_range
    assert_messageset_ok_with 1..5
  end
  def test_allows_array
    assert_messageset_ok_with [1,2,3,8]
  end
  def test_allows_string_range
    assert_messageset_ok_with "1:*"
  end

  
  ### Formatting Tests
  
  def assert_formats_as(expected, from)
    ms = Net::IMAP::MessageSet.new(from)
    fake_imap = IMAPTestStub.new
    ms.send_data(fake_imap)
    assert_equal(expected, fake_imap.strings[0])
  end

  def test_formats_integer
    assert_formats_as "1", 1
  end
  def test_formats_negative_one_as_star
    assert_formats_as "*", -1
  end
  def test_formats_range
    assert_formats_as '1:5', 1..5
  end

  def test_formats_array
    assert_formats_as '1,2,5', [1,2,5]
  end

  def test_formats_string_range
    assert_formats_as '1:*', '1:*'
  end
end
