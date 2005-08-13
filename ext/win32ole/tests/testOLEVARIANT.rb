require 'test/unit'

require 'win32ole'

class TestWIN32OLE_VARIANT < Test::Unit::TestCase
  def test_new
    obj = WIN32OLE_VARIANT.new('foo')
    assert_instance_of(WIN32OLE_VARIANT, obj)
  end

  def test_new_no_argument
    ex = nil
    begin
      obj = WIN32OLE_VARIANT.new
    rescue ArgumentError
      ex = $!
    end
    assert_instance_of(ArgumentError, ex)
    assert_equal("wrong number of arguments (0 for 1..3)", ex.message);
  end

  def test_new_one_argument
    ex = nil
    begin
      obj = WIN32OLE_VARIANT.new('foo')
    rescue
      ex = $!
    end
    assert_equal(nil, ex);
  end

  def test_value
    obj = WIN32OLE_VARIANT.new('foo')
    assert_equal('foo', obj.value)
  end

  def test_new_2_argument
    ex = nil
    obj = nil
    begin
      obj = WIN32OLE_VARIANT.new('foo', WIN32OLE::VARIANT::VT_BSTR|WIN32OLE::VARIANT::VT_BYREF)
    rescue
      ex = $!
    end
    assert_equal('foo', obj.value);
  end

  def test_new_2_argument2
    ex = nil
    obj = nil
    begin
      obj = WIN32OLE_VARIANT.new('foo', WIN32OLE::VARIANT::VT_BSTR)
    rescue
      ex = $!
    end
    assert_equal('foo', obj.value);
  end

  def test_conversion_num2str
    obj = WIN32OLE_VARIANT.new(124, WIN32OLE::VARIANT::VT_BSTR)
    assert_equal("124", obj.value);
  end

  def test_conversion_str2date
    obj = WIN32OLE_VARIANT.new("2004-12-24 12:24:45", WIN32OLE::VARIANT::VT_DATE)
    assert_equal("2004/12/24 12:24:45", obj.value)
  end

  def test_conversion_str2cy
    obj = WIN32OLE_VARIANT.new("\\10,000", WIN32OLE::VARIANT::VT_CY)
    assert_equal("10000", obj.value)
  end

end
