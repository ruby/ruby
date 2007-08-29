require 'test/unit'
require 'kconv'

class TestKconv < Test::Unit::TestCase
  EUC_STR = "\
\xa5\xaa\xa5\xd6\xa5\xb8\xa5\xa7\xa5\xaf\xa5\xc8\xbb\xd8\xb8\xfe\
\xa5\xd7\xa5\xed\xa5\xb0\xa5\xe9\xa5\xdf\xa5\xf3\xa5\xb0\xb8\xc0\xb8\xec
\x52\x75\x62\x79"
  UTF8_STR = "\
\xe3\x82\xaa\xe3\x83\x96\xe3\x82\xb8\xe3\x82\xa7\
\xe3\x82\xaf\xe3\x83\x88\xe6\x8c\x87\xe5\x90\x91\
\xe3\x83\x97\xe3\x83\xad\xe3\x82\xb0\xe3\x83\xa9\xe3\x83\x9f\
\xe3\x83\xb3\xe3\x82\xb0\xe8\xa8\x80\xe8\xaa\x9e
\x52\x75\x62\x79"
  SJIS_STR = "\
\x83\x49\x83\x75\x83\x57\x83\x46\x83\x4e\x83\x67\x8e\x77\x8c\xfc\
\x83\x76\x83\x8d\x83\x4f\x83\x89\x83\x7e\x83\x93\x83\x4f\x8c\xbe\x8c\xea
\x52\x75\x62\x79"
  JIS_STR = "\
\x1b\x24\x42\x25\x2a\x25\x56\x25\x38\x25\x27\x25\x2f\x25\x48\x3b\x58\x38\x7e\
\x25\x57\x25\x6d\x25\x30\x25\x69\x25\x5f\x25\x73\x25\x30\x38\x40\x38\x6c\x1b\x28\x42
\x52\x75\x62\x79"

  def test_eucjp
    assert(EUC_STR.iseuc)
    assert_equal(::Kconv::EUC, Kconv.guess(EUC_STR))
    assert_equal(EUC_STR, EUC_STR.toeuc)
    assert_equal(EUC_STR, SJIS_STR.toeuc)
    assert_equal(EUC_STR, UTF8_STR.toeuc)
    assert_equal(EUC_STR, JIS_STR.toeuc)
    assert_equal(EUC_STR, EUC_STR.kconv(::NKF::EUC))
    assert_equal(EUC_STR, SJIS_STR.kconv(::NKF::EUC))
    assert_equal(EUC_STR, UTF8_STR.kconv(::NKF::EUC))
    assert_equal(EUC_STR, JIS_STR.kconv(::NKF::EUC))
  end
  def test_shiftjis
    assert(SJIS_STR.issjis)
    assert_equal(::Kconv::SJIS, Kconv.guess(SJIS_STR))
    assert_equal(SJIS_STR, EUC_STR.tosjis)
    assert_equal(SJIS_STR, SJIS_STR.tosjis)
    assert_equal(SJIS_STR, UTF8_STR.tosjis)
    assert_equal(SJIS_STR, JIS_STR.tosjis)
    assert_equal(SJIS_STR, EUC_STR.kconv(::NKF::SJIS))
    assert_equal(SJIS_STR, SJIS_STR.kconv(::NKF::SJIS))
    assert_equal(SJIS_STR, UTF8_STR.kconv(::NKF::SJIS))
    assert_equal(SJIS_STR, JIS_STR.kconv(::NKF::SJIS))
  end
  def test_utf8
    assert(UTF8_STR.isutf8)
    assert_equal(::Kconv::UTF8, Kconv.guess(UTF8_STR))
    assert_equal(UTF8_STR, EUC_STR.toutf8)
    assert_equal(UTF8_STR, SJIS_STR.toutf8)
    assert_equal(UTF8_STR, UTF8_STR.toutf8)
    assert_equal(UTF8_STR, JIS_STR.toutf8)
    assert_equal(UTF8_STR, EUC_STR.kconv(::NKF::UTF8))
    assert_equal(UTF8_STR, SJIS_STR.kconv(::NKF::UTF8))
    assert_equal(UTF8_STR, UTF8_STR.kconv(::NKF::UTF8))
    assert_equal(UTF8_STR, JIS_STR.kconv(::NKF::UTF8))
  end
  def test_jis
    assert_equal(::Kconv::JIS, Kconv.guess(JIS_STR))
    assert_equal(JIS_STR, EUC_STR.tojis)
    assert_equal(JIS_STR, SJIS_STR.tojis)
    assert_equal(JIS_STR, UTF8_STR.tojis)
    assert_equal(JIS_STR, JIS_STR.tojis)
    assert_equal(JIS_STR, EUC_STR.kconv(::NKF::JIS))
    assert_equal(JIS_STR, SJIS_STR.kconv(::NKF::JIS))
    assert_equal(JIS_STR, UTF8_STR.kconv(::NKF::JIS))
    assert_equal(JIS_STR, JIS_STR.kconv(::NKF::JIS))
  end
end
