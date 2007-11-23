require 'test/unit'

class TestM17N < Test::Unit::TestCase
  def assert_encoding(encname, actual, message=nil)
    assert_equal(Encoding.find(encname), actual, message)
  end

  def a(str) str.force_encoding("ASCII-8BIT") end
  def e(str) str.force_encoding("EUC-JP") end
  def s(str) str.force_encoding("Shift_JIS") end
  def u(str) str.force_encoding("UTF-8") end

  def test_string_ascii_literal
    assert_encoding("ASCII-8BIT", eval(a(%{""})).encoding)
    assert_encoding("ASCII-8BIT", eval(a(%{"a"})).encoding)
  end

  def test_string_euc_literal
    assert_encoding("ASCII-8BIT", eval(e(%{""})).encoding)
    assert_encoding("ASCII-8BIT", eval(e(%{"a"})).encoding)
    assert_encoding("EUC-JP", eval(e(%{"\xa1\xa1"})).encoding)
    assert_encoding("EUC-JP", eval(e(%{"\\xa1\\xa1"})).encoding)
    assert_encoding("ASCII-8BIT", eval(e(%{"\\x20"})).encoding)
    assert_encoding("ASCII-8BIT", eval(e(%{"\\n"})).encoding)
    assert_encoding("EUC-JP", eval(e(%{"\\x80"})).encoding)
  end

  def test_regexp_too_short_multibyte_character
    assert_raise(SyntaxError) { eval('/\xfe/e') }
    assert_raise(SyntaxError) { eval('/\x8e/e') }
    assert_raise(SyntaxError) { eval('/\x8f/e') }
    assert_raise(SyntaxError) { eval('/\x8f\xa1/e') }
    assert_raise(SyntaxError) { eval('/\xef/s') }
    assert_raise(SyntaxError) { eval('/\xc0/u') }
    assert_raise(SyntaxError) { eval('/\xe0\x80/u') }
    assert_raise(SyntaxError) { eval('/\xf0\x80\x80/u') }
    assert_raise(SyntaxError) { eval('/\xf8\x80\x80\x80/u') }
    assert_raise(SyntaxError) { eval('/\xfc\x80\x80\x80\x80/u') }

    # raw 8bit
    #assert_raise(SyntaxError) { eval("/\xfe/e") }
    #assert_raise(SyntaxError) { eval("/\xc0/u") }

    # invalid suffix
    #assert_raise(SyntaxError) { eval('/\xc0\xff/u') }
    #assert_raise(SyntaxError) { eval('/\xc0\x20/u') }
  end

  def test_regexp_generic
    r = /a/
    assert_encoding("ASCII-8BIT", r.encoding)
    assert_equal(0, r =~ a("a"))
    assert_equal(0, r =~ e("a"))
    assert_equal(0, r =~ s("a"))
    assert_equal(0, r =~ u("a"))

    # "\xc0\xa1" is a valid sequence for ASCII-8BIT, EUC-JP, Shift_JIS and UTF-8.
    assert_equal(nil, r =~ a("\xc0\xa1"))
    assert_equal(nil, r =~ e("\xc0\xa1"))
    assert_equal(nil, r =~ s("\xc0\xa1"))
    assert_equal(nil, r =~ u("\xc0\xa1"))

    r = eval(a(%{/\xc0\xa1/}))
    assert_encoding("ASCII-8BIT", r.encoding)
    assert_equal(nil, r =~ a("a"))
    assert_equal(nil, r =~ e("a"))
    assert_equal(nil, r =~ s("a"))
    assert_equal(nil, r =~ u("a"))
    assert_equal(0, r =~ a("\xc0\xa1"))
    assert_raise(ArgumentError) { r =~ e("\xc0\xa1") }
    assert_raise(ArgumentError) { r =~ s("\xc0\xa1") }
    assert_raise(ArgumentError) { r =~ u("\xc0\xa1") }

    # xxx: /\xc0\xa1/ should be restricted only for ASCII-8BIT?
    # r = /\xc0\xa1/
    # assert_encoding("ASCII-8BIT", r.encoding)
    # assert_equal(nil, r =~ a("a"))
    # assert_equal(nil, r =~ e("a"))
    # assert_equal(nil, r =~ s("a"))
    # assert_equal(nil, r =~ u("a"))
    # assert_equal(0, r =~ a("\xc0\xa1"))
    # assert_equal(0, r =~ e("\xc0\xa1")) # xxx
    # assert_equal(0, r =~ s("\xc0\xa1")) # xxx
    # assert_equal(0, r =~ u("\xc0\xa1")) # xxx
  end

  def test_regexp_ascii
    r = /a/n
    assert_encoding("ASCII-8BIT", r.encoding)
    assert_equal(0, r =~ a("a"))
    assert_equal(0, r =~ e("a"))
    assert_equal(0, r =~ s("a"))
    assert_equal(0, r =~ u("a"))
    assert_equal(nil, r =~ a("\xc0\xa1"))
    assert_raise(ArgumentError) { r =~ e("\xc0\xa1") }
    assert_raise(ArgumentError) { r =~ s("\xc0\xa1") }
    assert_raise(ArgumentError) { r =~ u("\xc0\xa1") }

    r = /\xc0\xa1/n
    assert_encoding("ASCII-8BIT", r.encoding)
    assert_equal(nil, r =~ a("a"))
    assert_equal(nil, r =~ e("a"))
    assert_equal(nil, r =~ s("a"))
    assert_equal(nil, r =~ u("a"))
    assert_equal(0, r =~ a("\xc0\xa1"))
    assert_raise(ArgumentError) { r =~ e("\xc0\xa1") }
    assert_raise(ArgumentError) { r =~ s("\xc0\xa1") }
    assert_raise(ArgumentError) { r =~ u("\xc0\xa1") }

    r = eval(%{/\xc0\xa1/n}.force_encoding("ASCII-8BIT"))
    assert_encoding("ASCII-8BIT", r.encoding)
    assert_equal(nil, r =~ a("a"))
    assert_equal(nil, r =~ e("a"))
    assert_equal(nil, r =~ s("a"))
    assert_equal(nil, r =~ u("a"))
    assert_equal(0, r =~ a("\xc0\xa1"))
    assert_raise(ArgumentError) { r =~ e("\xc0\xa1") }
    assert_raise(ArgumentError) { r =~ s("\xc0\xa1") }
    assert_raise(ArgumentError) { r =~ u("\xc0\xa1") }

    r = eval(%q{/\xc0\xa1/}.force_encoding("ASCII-8BIT"))
    assert_encoding("ASCII-8BIT", r.encoding)
    assert_equal(nil, r =~ a("a"))
    assert_equal(nil, r =~ e("a"))
    assert_equal(nil, r =~ s("a"))
    assert_equal(nil, r =~ u("a"))
    assert_equal(0, r =~ a("\xc0\xa1"))
    # assert_raise(ArgumentError) { r =~ e("\xc0\xa1") }
    # assert_raise(ArgumentError) { r =~ s("\xc0\xa1") }
    # assert_raise(ArgumentError) { r =~ u("\xc0\xa1") }

  end

  def test_regexp_euc
    r = /a/e
    assert_encoding("EUC-JP", r.encoding)
    assert_equal(0, r =~ a("a"))
    assert_equal(0, r =~ e("a"))
    assert_equal(0, r =~ s("a"))
    assert_equal(0, r =~ u("a"))
    assert_raise(ArgumentError) { r =~ a("\xc0\xa1") }
    assert_equal(nil, r =~ e("\xc0\xa1"))
    assert_raise(ArgumentError) { r =~ s("\xc0\xa1") }
    assert_raise(ArgumentError) { r =~ u("\xc0\xa1") }

    r = /\xc0\xa1/e
    assert_encoding("EUC-JP", r.encoding)
    assert_equal(nil, r =~ a("a"))
    assert_equal(nil, r =~ e("a"))
    assert_equal(nil, r =~ s("a"))
    assert_equal(nil, r =~ u("a"))
    assert_raise(ArgumentError) { r =~ a("\xc0\xa1") }
    assert_equal(0, r =~ e("\xc0\xa1"))
    assert_raise(ArgumentError) { r =~ s("\xc0\xa1") }
    assert_raise(ArgumentError) { r =~ u("\xc0\xa1") }

    r = eval(%{/\xc0\xa1/}.force_encoding("EUC-JP"))
    assert_encoding("EUC-JP", r.encoding)
    assert_equal(nil, r =~ a("a"))
    assert_equal(nil, r =~ e("a"))
    assert_equal(nil, r =~ s("a"))
    assert_equal(nil, r =~ u("a"))
    assert_raise(ArgumentError) { r =~ a("\xc0\xa1") }
    assert_equal(0, r =~ e("\xc0\xa1"))
    assert_raise(ArgumentError) { r =~ s("\xc0\xa1") }
    assert_raise(ArgumentError) { r =~ u("\xc0\xa1") }

    r = eval(%q{/\xc0\xa1/}.force_encoding("EUC-JP"))
    assert_encoding("EUC-JP", r.encoding)
    assert_equal(nil, r =~ a("a"))
    assert_equal(nil, r =~ e("a"))
    assert_equal(nil, r =~ s("a"))
    assert_equal(nil, r =~ u("a"))
    assert_raise(ArgumentError) { r =~ a("\xc0\xa1") }
    assert_equal(0, r =~ e("\xc0\xa1"))
    assert_raise(ArgumentError) { r =~ s("\xc0\xa1") }
    assert_raise(ArgumentError) { r =~ u("\xc0\xa1") }
  end

  def test_begin_end_offset
    str = e("\244\242\244\244\244\246\244\250\244\252a")
    assert(/(a)/ =~ str)
    assert_equal("a", $&)
    assert_equal(5, $~.begin(0))
    assert_equal(6, $~.end(0))
    assert_equal([5,6], $~.offset(0))
    assert_equal(5, $~.begin(1))
    assert_equal(6, $~.end(1))
    assert_equal([5,6], $~.offset(1))
  end

  def test_begin_end_offset_sjis
    str = s("\x81@@")
    assert(/@/ =~ str)
    assert_equal(s("\x81@"), $`)
    assert_equal("@", $&)
    assert_equal("", $')
    assert_equal([1,2], $~.offset(0))
  end

end
