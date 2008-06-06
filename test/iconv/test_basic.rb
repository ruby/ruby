require File.join(File.dirname(__FILE__), "utils.rb")

class TestIconv::Basic < TestIconv
  def test_euc2sjis
    iconv = Iconv.open('SHIFT_JIS', 'EUC-JP')
    str = iconv.iconv(EUCJ_STR)
    str << iconv.iconv(nil)
    assert_equal(SJIS_STR, str)
    iconv.close
  end

  def test_close
    iconv = Iconv.new('Shift_JIS', 'EUC-JP')
    output = ""
    begin
      output += iconv.iconv(EUCJ_STR)
      output += iconv.iconv(nil)
    ensure
      assert_respond_to(iconv, :close)
      assert_equal("", iconv.close)
      assert_equal(SJIS_STR, output)
    end
  end

  def test_open_without_block
    assert_respond_to(Iconv, :open)
    iconv = Iconv.open('SHIFT_JIS', 'EUC-JP')
    str = iconv.iconv(EUCJ_STR)
    str << iconv.iconv(nil)
    assert_equal(SJIS_STR, str )
    iconv.close
  end

  def test_open_with_block
    input = "#{EUCJ_STR}\n"*2
    output = ""
    Iconv.open("Shift_JIS", "EUC-JP") do |cd|
      input.each_line do |s|
        output << cd.iconv(s)
      end
      output << cd.iconv(nil)
    end
    assert_equal("#{SJIS_STR}\n"*2, output)
  end

  def test_unknown_encoding
    assert_raise(Iconv::InvalidEncoding) { Iconv.iconv("utf-8", "X-UKNOWN", "heh") }
  end
end if defined?(TestIconv)
