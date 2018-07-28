# coding: utf-8
# frozen_string_literal: false

# Copyright Ayumu Nojima (野島 歩) and Martin J. Dürst (duerst@it.aoyama.ac.jp)

require 'test/unit'
require 'unicode_normalize/normalize'

class TestUnicodeNormalize < Test::Unit::TestCase

  UNICODE_VERSION = RbConfig::CONFIG['UNICODE_VERSION']
  path = File.expand_path("../enc/unicode/data/#{UNICODE_VERSION}", __dir__)
  UNICODE_DATA_PATH = File.directory?("#{path}/ucd") ? "#{path}/ucd" : path

  def self.expand_filename(basename)
    File.expand_path("#{basename}.txt", UNICODE_DATA_PATH)
  end
end

%w[NormalizationTest].all? {|f|
  File.exist?(TestUnicodeNormalize.expand_filename(f))
} and
class TestUnicodeNormalize
  NormTest = Struct.new :source, :NFC, :NFD, :NFKC, :NFKD, :line

  def self.read_tests
    lines = IO.readlines(expand_filename('NormalizationTest'), encoding: 'utf-8')
    firstline = lines.shift
    define_method "test_0_normalizationtest_firstline" do
      assert_include(firstline, "NormalizationTest-#{UNICODE_VERSION}.txt")
    end
    lines
    .collect.with_index { |linedata, linenumber| [linedata, linenumber]}
    .reject { |line| line[0] =~ /^[\#@]/ }
    .collect do |line|
      NormTest.new(*(line[0].split(';').take(5).collect do |code_string|
        code_string.split(/\s/).collect { |cp| cp.to_i(16) }.pack('U*')
      end + [line[1]+1]))
    end
  end

  def to_codepoints(string)
    string.codepoints.collect { |cp| cp.to_s(16).upcase.rjust(4, '0') }
  end

  begin
    @@tests ||= read_tests
  rescue Errno::ENOENT => e
    @@tests ||= []
  end

  def self.generate_test_normalize(target, normalization, source, prechecked)
    define_method "test_normalize_to_#{target}_from_#{source}_with_#{normalization}" do
      expected = actual = test = nil
      mesg = proc {"#{to_codepoints(expected)} expected but was #{to_codepoints(actual)} on line #{test[:line]} (#{normalization})"}
      @@tests.each do |t|
        test = t
        if prechecked.nil? or test[prechecked]==test[source]
          expected = test[target]
          actual = test[source].unicode_normalize(normalization)
          assert_equal expected, actual, mesg
        end
      end
    end
  end

#      source; NFC; NFD; NFKC; NFKD
#    NFC
#      :NFC ==  toNFC(:source) ==  toNFC(:NFC) ==  toNFC(:NFD)
  generate_test_normalize :NFC, :nfc, :source, nil
  generate_test_normalize :NFC, :nfc, :NFC, :source
  generate_test_normalize :NFC, :nfc, :NFD, :source
#      :NFKC ==  toNFC(:NFKC) ==  toNFC(:NFKD)
  generate_test_normalize :NFKC, :nfc, :NFKC, nil
  generate_test_normalize :NFKC, :nfc, :NFKD, :NFKC
#
#    NFD
#      :NFD ==  toNFD(:source) ==  toNFD(:NFC) ==  toNFD(:NFD)
  generate_test_normalize :NFD, :nfd, :source, nil
  generate_test_normalize :NFD, :nfd, :NFC, :source
  generate_test_normalize :NFD, :nfd, :NFD, :source
#      :NFKD ==  toNFD(:NFKC) ==  toNFD(:NFKD)
  generate_test_normalize :NFKD, :nfd, :NFKC, nil
  generate_test_normalize :NFKD, :nfd, :NFKD, :NFKC
#
#    NFKC
#      :NFKC == toNFKC(:source) == toNFKC(:NFC) == toNFKC(:NFD) == toNFKC(:NFKC) == toNFKC(:NFKD)
  generate_test_normalize :NFKC, :nfkc, :source, nil
  generate_test_normalize :NFKC, :nfkc, :NFC, :source
  generate_test_normalize :NFKC, :nfkc, :NFD, :source
  generate_test_normalize :NFKC, :nfkc, :NFKC, :NFC
  generate_test_normalize :NFKC, :nfkc, :NFKD, :NFD
#
#    NFKD
#      :NFKD == toNFKD(:source) == toNFKD(:NFC) == toNFKD(:NFD) == toNFKD(:NFKC) == toNFKD(:NFKD)
  generate_test_normalize :NFKD, :nfkd, :source, nil
  generate_test_normalize :NFKD, :nfkd, :NFC, :source
  generate_test_normalize :NFKD, :nfkd, :NFD, :source
  generate_test_normalize :NFKD, :nfkd, :NFKC, :NFC
  generate_test_normalize :NFKD, :nfkd, :NFKD, :NFD

  def self.generate_test_check_true(source, normalization)
    define_method "test_check_true_#{source}_as_#{normalization}" do
      test = nil
      mesg = proc {"#{to_codepoints(test[source])} should check as #{normalization} but does not on line #{test[:line]}"}
      @@tests.each do |t|
        test = t
        actual = test[source].unicode_normalized?(normalization)
        assert_equal true, actual, mesg
      end
    end
  end

  def self.generate_test_check_false(source, compare, normalization)
    define_method "test_check_false_#{source}_as_#{normalization}" do
      test = nil
      mesg = proc {"#{to_codepoints(test[source])} should not check as #{normalization} but does on line #{test[:line]}"}
      @@tests.each do |t|
        test = t
        if test[source] != test[compare]
          actual = test[source].unicode_normalized?(normalization)
          assert_equal false, actual, mesg
        end
      end
    end
  end

  generate_test_check_true :NFC, :nfc
  generate_test_check_true :NFD, :nfd
  generate_test_check_true :NFKC, :nfc
  generate_test_check_true :NFKC, :nfkc
  generate_test_check_true :NFKD, :nfd
  generate_test_check_true :NFKD, :nfkd

  generate_test_check_false :source, :NFD, :nfd
  generate_test_check_false :NFC, :NFD, :nfd
  generate_test_check_false :NFKC, :NFKD, :nfd
  generate_test_check_false :source, :NFC, :nfc
  generate_test_check_false :NFD, :NFC, :nfc
  generate_test_check_false :NFKD, :NFKC, :nfc
  generate_test_check_false :source, :NFKD, :nfkd
  generate_test_check_false :NFC, :NFKD, :nfkd
  generate_test_check_false :NFD, :NFKD, :nfkd
  generate_test_check_false :NFKC, :NFKD, :nfkd
  generate_test_check_false :source, :NFKC, :nfkc
  generate_test_check_false :NFC, :NFKC, :nfkc
  generate_test_check_false :NFD, :NFKC, :nfkc
  generate_test_check_false :NFKD, :NFKC, :nfkc
end

class TestUnicodeNormalize
  def test_non_UTF_8
    assert_equal "\u1E0A".encode('UTF-16BE'), "D\u0307".encode('UTF-16BE').unicode_normalize(:nfc)
    assert_equal true, "\u1E0A".encode('UTF-16BE').unicode_normalized?(:nfc)
    assert_equal false, "D\u0307".encode('UTF-16BE').unicode_normalized?(:nfc)
  end

  def test_singleton_with_accents
    assert_equal "\u0136", "\u212A\u0327".unicode_normalize(:nfc)
  end

  def test_partial_jamo_compose
    assert_equal "\uAC01", "\uAC00\u11A8".unicode_normalize(:nfc)
  end

  def test_partial_jamo_decompose
    assert_equal "\u1100\u1161\u11A8", "\uAC00\u11A8".unicode_normalize(:nfd)
  end

  # preventive tests for (non-)bug #14934
  def test_no_trailing_jamo
    assert_equal "\u1100\u1176\u11a8", "\u1100\u1176\u11a8".unicode_normalize(:nfc)
    assert_equal "\uae30\u11a7",       "\u1100\u1175\u11a7".unicode_normalize(:nfc)
    assert_equal "\uae30\u11c3",       "\u1100\u1175\u11c3".unicode_normalize(:nfc)
  end

  def test_hangul_plus_accents
    assert_equal "\uAC00\u0323\u0300", "\uAC00\u0300\u0323".unicode_normalize(:nfc)
    assert_equal "\uAC00\u0323\u0300", "\u1100\u1161\u0300\u0323".unicode_normalize(:nfc)
    assert_equal "\u1100\u1161\u0323\u0300", "\uAC00\u0300\u0323".unicode_normalize(:nfd)
    assert_equal "\u1100\u1161\u0323\u0300", "\u1100\u1161\u0300\u0323".unicode_normalize(:nfd)
  end

  def test_raise_exception_for_non_unicode_encoding
    assert_raise(Encoding::CompatibilityError) { "abc".force_encoding('ISO-8859-1').unicode_normalize }
    assert_raise(Encoding::CompatibilityError) { "abc".force_encoding('ISO-8859-1').unicode_normalize! }
    assert_raise(Encoding::CompatibilityError) { "abc".force_encoding('ISO-8859-1').unicode_normalized? }
  end

  def test_us_ascii
    ascii_string = 'abc'.encode('US-ASCII')

    assert_equal ascii_string, ascii_string.unicode_normalize
    assert_equal ascii_string, ascii_string.unicode_normalize(:nfd)
    assert_equal ascii_string, ascii_string.unicode_normalize(:nfkc)
    assert_equal ascii_string, ascii_string.unicode_normalize(:nfkd)

    assert_equal ascii_string, ascii_string.dup.unicode_normalize!
    assert_equal ascii_string, ascii_string.dup.unicode_normalize!(:nfd)
    assert_equal ascii_string, ascii_string.dup.unicode_normalize!(:nfkc)
    assert_equal ascii_string, ascii_string.dup.unicode_normalize!(:nfkd)

    assert_equal true, ascii_string.unicode_normalized?
    assert_equal true, ascii_string.unicode_normalized?(:nfd)
    assert_equal true, ascii_string.unicode_normalized?(:nfkc)
    assert_equal true, ascii_string.unicode_normalized?(:nfkd)
  end
end
