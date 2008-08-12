require 'test/unit'

class TestEncodingConverter < Test::Unit::TestCase
  def assert_econv(ret_expected, src_expected, dst_expected, from, to, src, dst, flags=0)
    ec = Encoding::Converter.new(from, to)
    ret = ec.primitive_convert(src, dst, flags)
    assert_equal(ret_expected, ret)
    assert_equal(src_expected, src)
    assert_equal(dst_expected, dst)
  end

  def test_eucjp_to_utf8
    assert_econv(:finished, "", "", "EUC-JP", "UTF-8", "", "")
    assert_econv(:ibuf_empty, "", "", "EUC-JP", "UTF-8", "", "", Encoding::Converter::PARTIAL_INPUT)
    assert_econv(:finished, "", "", "EUC-JP", "UTF-8", "", " "*10)
    assert_econv(:obuf_full, "", "", "EUC-JP", "UTF-8", "a", "")
  end

  def test_invalid
    assert_econv(:invalid_input, "", "", "EUC-JP", "UTF-8", "\x80", " "*10)
    assert_econv(:invalid_input, "", "a", "EUC-JP", "UTF-8", "a\x80", " "*10)
    assert_econv(:invalid_input, "\x80", "a", "EUC-JP", "UTF-8", "a\x80\x80", " "*10)
  end
end
