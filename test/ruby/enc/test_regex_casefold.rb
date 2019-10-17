# Copyright Kimihito Matsui (松井 仁人) and Martin J. Dürst (duerst@it.aoyama.ac.jp)

require "test/unit"

class TestCaseFold < Test::Unit::TestCase

  UNICODE_VERSION = RbConfig::CONFIG['UNICODE_VERSION']
  path = File.expand_path("../../../enc/unicode/data/#{UNICODE_VERSION}", __dir__)
  UNICODE_DATA_PATH = File.directory?("#{path}/ucd") ? "#{path}/ucd" : path
  CaseTest = Struct.new :source, :target, :kind, :line

  def check_downcase_properties(expected, start, *flags)
    assert_equal expected, start.downcase(*flags)
    temp = start
    assert_equal expected, temp.downcase!(*flags)
    assert_equal expected, expected.downcase(*flags)
    temp = expected
    assert_nil   temp.downcase!(*flags)
  end

  def read_tests
    IO.readlines("#{UNICODE_DATA_PATH}/CaseFolding.txt", encoding: Encoding::ASCII_8BIT)
    .collect.with_index { |linedata, linenumber| [linenumber.to_i+1, linedata.chomp] }
    .reject { |number, data| data =~ /^(#|$)/ }
    .collect do |linenumber, linedata|
      data, _ = linedata.split(/#\s*/)
      code, kind, result, _ = data.split(/;\s*/)
      CaseTest.new code.to_i(16).chr('UTF-8'),
                   result.split(/ /).collect { |hex| hex.to_i(16) }.pack('U*'),
                   kind, linenumber
    end.select { |test| test.kind=='C' }
  end

  def to_codepoints(string)
    string.codepoints.collect { |cp| cp.to_s(16).upcase.rjust(4, '0') }
  end

  def setup
    @@tests ||= read_tests
  rescue Errno::ENOENT => e
    @@tests ||= []
    skip e.message
  end

  def self.generate_test_casefold(encoding)
    define_method "test_mbc_case_fold_#{encoding}" do
      @@tests.each do |test|
        begin
          source = test.source.encode encoding
          target = test.target.encode encoding
          assert_equal 5, "12345#{target}67890" =~ /#{source}/i,
              "12345#{to_codepoints(target)}67890 and /#{to_codepoints(source)}/ do not match case-insensitive " +
              "(CaseFolding.txt line #{test[:line]})"
        rescue Encoding::UndefinedConversionError
        end
      end
    end

    define_method "test_get_case_fold_codes_by_str_#{encoding}" do
      @@tests.each do |test|
        begin
          source = test.source.encode encoding
          target = test.target.encode encoding
          assert_equal 5, "12345#{source}67890" =~ /#{target}/i,
              "12345#{to_codepoints(source)}67890 and /#{to_codepoints(target)}/ do not match case-insensitive " +
              "(CaseFolding.txt line #{test[:line]}), " +
              "error may also be triggered by mbc_case_fold"
        rescue Encoding::UndefinedConversionError
        end
      end
    end

    define_method "test_apply_all_case_fold_#{encoding}" do
      @@tests.each do |test|
        begin
          source = test.source.encode encoding
          target = test.target.encode encoding
          reg = '\p{Upper}'
          regexp = Regexp.compile reg.encode(encoding)
          regexpi = Regexp.compile reg.encode(encoding), Regexp::IGNORECASE
            assert_equal 5, "12345#{target}67890" =~ regexpi,
                "12345#{to_codepoints(target)}67890 and /#{reg}/i do not match " +
                "(CaseFolding.txt line #{test[:line]})"
        rescue Encoding::UndefinedConversionError
          source = source
          regexp = regexp
        end
      end
    end
  end

  def test_downcase_fold
    @@tests.each do |test|
      check_downcase_properties test.target, test.source, :fold
    end
  end

  # start with good encodings only
  generate_test_casefold 'US-ASCII'
  generate_test_casefold 'ISO-8859-1'
  generate_test_casefold 'ISO-8859-2'
  generate_test_casefold 'ISO-8859-3'
  generate_test_casefold 'ISO-8859-4'
  generate_test_casefold 'ISO-8859-5'
  generate_test_casefold 'ISO-8859-6'
  # generate_test_casefold 'ISO-8859-7'
  generate_test_casefold 'ISO-8859-8'
  generate_test_casefold 'ISO-8859-9'
  generate_test_casefold 'ISO-8859-10'
  generate_test_casefold 'ISO-8859-11'
  generate_test_casefold 'ISO-8859-13'
  generate_test_casefold 'ISO-8859-14'
  generate_test_casefold 'ISO-8859-15'
  generate_test_casefold 'ISO-8859-16'
  generate_test_casefold 'Windows-1250'
  # generate_test_casefold 'Windows-1251'
  generate_test_casefold 'Windows-1252'
  generate_test_casefold 'koi8-r'
  generate_test_casefold 'koi8-u'
end
