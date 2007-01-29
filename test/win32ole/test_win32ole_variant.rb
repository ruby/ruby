begin
  require 'win32ole'
rescue LoadError
end
require "test/unit"

if defined?(WIN32OLE_VARIANT)

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
      obj = WIN32OLE_VARIANT.new('foo', WIN32OLE::VARIANT::VT_BSTR|WIN32OLE::VARIANT::VT_BYREF)
      assert_equal('foo', obj.value);
    end

    def test_new_2_argument2
      obj = WIN32OLE_VARIANT.new('foo', WIN32OLE::VARIANT::VT_BSTR)
      assert_equal('foo', obj.value);
    end

    def test_conversion_num2str
      obj = WIN32OLE_VARIANT.new(124, WIN32OLE::VARIANT::VT_BSTR)
      assert_equal("124", obj.value);
    end

    def test_conversion_float2int
      obj = WIN32OLE_VARIANT.new(12.345, WIN32OLE::VARIANT::VT_I4)
      assert_equal(12, obj.value)
    end

    def test_conversion_str2num
      obj = WIN32OLE_VARIANT.new("12.345", WIN32OLE::VARIANT::VT_R8)
      assert_equal(12.345, obj.value)
    end

    def test_conversion_ole_variant2ole_variant
      obj = WIN32OLE_VARIANT.new("12.345", WIN32OLE::VARIANT::VT_R4)
      obj = WIN32OLE_VARIANT.new(obj, WIN32OLE::VARIANT::VT_I4)
      assert_equal(12, obj.value)
    end

    def test_conversion_str2date
      obj = WIN32OLE_VARIANT.new("2004-12-24 12:24:45", WIN32OLE::VARIANT::VT_DATE)
      assert_equal("2004/12/24 12:24:45", obj.value)
    end

    def test_conversion_time2date
      dt = Time.mktime(2004, 12, 24, 12, 24, 45)
      obj = WIN32OLE_VARIANT.new(dt, WIN32OLE::VARIANT::VT_DATE)
      assert_equal("2004/12/24 12:24:45", obj.value)
    end

    def test_conversion_str2cy
      begin 
        WIN32OLE.locale = 0x0411 # set locale Japanese
        obj = WIN32OLE_VARIANT.new("\\10,000", WIN32OLE::VARIANT::VT_CY)
        assert_equal("10000", obj.value)
      ensure
        WIN32OLE.locale = WIN32OLE::LOCALE_SYSTEM_DEFAULT
      end
    end

    def test_create_vt_array
      obj = WIN32OLE_VARIANT.new([1.2, 2.3], WIN32OLE::VARIANT::VT_ARRAY|WIN32OLE::VARIANT::VT_R8)
      assert_equal([1.2, 2.3], obj.value)
    end

    def test_create_vt_array_exc
      exc = assert_raise(TypeError) {
        obj = WIN32OLE_VARIANT.new(1, WIN32OLE::VARIANT::VT_ARRAY);
      }
      assert_match(/wrong argument type Fixnum \(expected Array\)/, exc.message)
    end

    def test_create_vt_array_str2ui1array
      obj = WIN32OLE_VARIANT.new("ABC", WIN32OLE::VARIANT::VT_ARRAY|WIN32OLE::VARIANT::VT_UI1)
      assert_equal("ABC", obj.value)

      obj = WIN32OLE_VARIANT.new([65, 0].pack("C*"), WIN32OLE::VARIANT::VT_ARRAY|WIN32OLE::VARIANT::VT_UI1)
      assert_equal([65, 0].pack("C*"), obj.value)

    end

    def test_create_vt_array_int
      obj = WIN32OLE_VARIANT.new([65, 0], WIN32OLE::VARIANT::VT_ARRAY|WIN32OLE::VARIANT::VT_UI1)
      assert_equal([65, 0].pack("C*"), obj.value)

      obj = WIN32OLE_VARIANT.new([65, 0])
      assert_equal([65, 0], obj.value)

      obj = WIN32OLE_VARIANT.new([65, 0], WIN32OLE::VARIANT::VT_I2|WIN32OLE::VARIANT::VT_ARRAY)
      assert_equal([65, 0], obj.value)
    end

    def test_create_nil_dispatch
      var = WIN32OLE_VARIANT.new(nil, WIN32OLE::VARIANT::VT_DISPATCH)
      assert_nil(var.value)
    end

    def test_create_variant_byref
      obj = WIN32OLE_VARIANT.new("Str", WIN32OLE::VARIANT::VT_VARIANT|WIN32OLE::VARIANT::VT_BYREF);
      assert_equal("Str", obj.value);
    end

    def test_vartype
      obj = WIN32OLE_VARIANT.new("Str")
      assert_equal(WIN32OLE::VARIANT::VT_BSTR, obj.vartype)
    end

    def test_c_nothing
      assert_nil(WIN32OLE_VARIANT::Nothing.value)
    end

    def test_c_empty
      assert_nil(WIN32OLE_VARIANT::Empty.value)
    end

    def test_c_null
      assert_nil(WIN32OLE_VARIANT::Null.value)
    end


  end
end
