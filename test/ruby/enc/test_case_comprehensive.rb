# frozen_string_literal: true
# Copyright © 2016 Martin J. Dürst (duerst@it.aoyama.ac.jp)

require "test/unit"

class TestComprehensiveCaseMapping < Test::Unit::TestCase
  UNICODE_VERSION = RbConfig::CONFIG['UNICODE_VERSION']
  path = File.expand_path("../../../enc/unicode/data/#{UNICODE_VERSION}", __dir__)
  UNICODE_DATA_PATH = File.directory?("#{path}/ucd") ? "#{path}/ucd" : path

  def self.hex2utf8(s)
    s.split(' ').map { |c| c.to_i(16) }.pack('U*')
  end

  def self.expand_filename(basename)
    File.expand_path("#{UNICODE_DATA_PATH}/#{basename}.txt", __dir__)
  end

  def self.data_files_available?
    %w[UnicodeData CaseFolding SpecialCasing].all? do |f|
      File.exist?(expand_filename(f))
    end
  end

  def test_data_files_available
    unless TestComprehensiveCaseMapping.data_files_available?
      omit "Unicode data files not available in #{UNICODE_DATA_PATH}."
    end
  end
end

TestComprehensiveCaseMapping.data_files_available? and  class TestComprehensiveCaseMapping
  (CaseTest = Struct.new(:method_name, :attributes, :first_data, :follow_data)).class_eval do
    def initialize(method_name, attributes, first_data, follow_data=first_data)
      super
    end
  end

  def self.read_data_file(filename)
    File.foreach(expand_filename(filename), encoding: Encoding::ASCII_8BIT) do |line|
      if $. == 1
        if filename == 'UnicodeData'
        elsif line.start_with?("# #{filename}-#{UNICODE_VERSION}.txt")
        else
          raise "File Version Mismatch"
        end
      end
      next if /\A(?:[\#@]|\s*\z)|Surrogate/.match?(line)
      data = line.chomp.split('#')[0].split(/;\s*/, 15)
      code = data[0].to_i(16).chr(Encoding::UTF_8)
      yield code, data
    end
  end

  def self.read_data
    @@codepoints = []

    downcase  = Hash.new { |h, c| c }
    upcase    = Hash.new { |h, c| c }
    titlecase = Hash.new { |h, c| c }
    casefold  = Hash.new { |h, c| c }
    swapcase  = Hash.new { |h, c| c }
    turkic_upcase    = Hash.new { |h, c| upcase[c] }
    turkic_downcase  = Hash.new { |h, c| downcase[c] }
    turkic_titlecase = Hash.new { |h, c| titlecase[c] }
    turkic_swapcase  = Hash.new { |h, c| swapcase[c] }
    ascii_upcase     = Hash.new { |h, c| /\A[a-zA-Z]\z/.match?(c) ? upcase[c] : c }
    ascii_downcase   = Hash.new { |h, c| /\A[a-zA-Z]\z/.match?(c) ? downcase[c] : c }
    ascii_titlecase  = Hash.new { |h, c| /\A[a-zA-Z]\z/.match?(c) ? titlecase[c] : c }
    ascii_swapcase   = Hash.new { |h, c| /\A[a-z]\z/.match?(c) ? upcase[c] : (/\A[A-Z]\z/.match?(c) ? downcase[c] : c) }

    read_data_file('UnicodeData') do |code, data|
      @@codepoints << code
      upcase[code] = hex2utf8 data[12] unless data[12].empty?
      downcase[code] = hex2utf8 data[13] unless data[13].empty?
      if code>="\u1C90" and code<="\u1CBF" # exception for Georgian: use lowercase for titlecase
        titlecase[code] = hex2utf8(data[13]) unless data[13].empty?
      else
        titlecase[code] = hex2utf8 data[14] unless data[14].empty?
      end
    end
    read_data_file('CaseFolding') do |code, data|
      casefold[code] = hex2utf8(data[2]) if data[1] =~ /^[CF]$/
    end

    read_data_file('SpecialCasing') do |code, data|
      case data[4]
      when ''
        upcase[code] = hex2utf8 data[3]
        downcase[code] = hex2utf8 data[1]
        titlecase[code] = hex2utf8 data[2]
      when /\Atr\s*/
        if data[4]!='tr After_I'
          turkic_upcase[code] = hex2utf8 data[3]
          turkic_downcase[code] = hex2utf8 data[1]
          turkic_titlecase[code] = hex2utf8 data[2]
        end
      end
    end

    @@codepoints.each do |c|
      if upcase[c] != c
        if downcase[c] != c
          swapcase[c] = turkic_swapcase[c] =
            case c
            when "\u01C5" then "\u0064\u017D"
            when "\u01C8" then "\u006C\u004A"
            when "\u01CB" then "\u006E\u004A"
            when "\u01F2" then "\u0064\u005A"
            else # Greek
              downcase[upcase[c][0]] + "\u0399"
            end
        else
          swapcase[c] = upcase[c]
          turkic_swapcase[c] = turkic_upcase[c]
        end
      else
        if downcase[c] != c
          swapcase[c] = downcase[c]
          turkic_swapcase[c] = turkic_downcase[c]
        end
      end
    end

    [
      CaseTest.new(:downcase,   [], downcase),
      CaseTest.new(:upcase,     [], upcase),
      CaseTest.new(:capitalize, [], titlecase, downcase),
      CaseTest.new(:swapcase,   [], swapcase),
      CaseTest.new(:downcase,   [:fold],       casefold),
      CaseTest.new(:upcase,     [:turkic],     turkic_upcase),
      CaseTest.new(:downcase,   [:turkic],     turkic_downcase),
      CaseTest.new(:capitalize, [:turkic],     turkic_titlecase, turkic_downcase),
      CaseTest.new(:swapcase,   [:turkic],     turkic_swapcase),
      CaseTest.new(:upcase,     [:ascii],      ascii_upcase),
      CaseTest.new(:downcase,   [:ascii],      ascii_downcase),
      CaseTest.new(:capitalize, [:ascii],      ascii_titlecase, ascii_downcase),
      CaseTest.new(:swapcase,   [:ascii],      ascii_swapcase),
    ]
  end

  def self.all_tests
    @@tests ||= read_data
  rescue Errno::ENOENT
    @@tests ||= []
  end

  def self.generate_unicode_case_mapping_tests(encoding)
    all_tests.each do |test|
      attributes = test.attributes.map(&:to_s).join '-'
      attributes.prepend '_' unless attributes.empty?
      define_method "test_#{encoding}_#{test.method_name}#{attributes}" do
        @@codepoints.each do |code|
          source = code.encode(encoding) * 5
          target = "#{test.first_data[code]}#{test.follow_data[code]*4}".encode(encoding)
          result = source.__send__(test.method_name, *test.attributes)
          assert_equal target, result,
            proc{"from #{code*5} (#{source.dump}) expected #{target.dump} but was #{result.dump}"}
        end
      end
    end
  end

  def self.generate_case_mapping_tests(encoding)
    all_tests
    # preselect codepoints to speed up testing for small encodings
    codepoints = @@codepoints.select do |code|
      begin
        code.encode(encoding)
        true
      rescue Encoding::UndefinedConversionError
        false
      end
    end
    all_tests.each do |test|
      attributes = test.attributes.map(&:to_s).join '-'
      attributes.prepend '_' unless attributes.empty?
      define_method "test_#{encoding}_#{test.method_name}#{attributes}" do
        codepoints.each do |code|
          begin
            source = code.encode(encoding) * 5
            begin
              target = "#{test.first_data[code]}#{test.follow_data[code]*4}".encode(encoding)
            rescue Encoding::UndefinedConversionError
              if test.first_data[code]=="i\u0307" or test.follow_data[code]=="i\u0307" # explicit dot above
                first_data = test.first_data[code]=="i\u0307" ? 'i' : test.first_data[code]
                follow_data = test.follow_data[code]=="i\u0307" ? 'i' : test.follow_data[code]
                target = "#{first_data}#{follow_data*4}".encode(encoding)
              elsif code =~ /i|I/ # special case for Turkic
                raise
              else
                target = source
              end
            end
            result = source.send(test.method_name, *test.attributes)
            assert_equal target, result,
              proc{"from #{code*5} (#{source.dump}) expected #{target.dump} but was #{result.dump}"}
          rescue Encoding::UndefinedConversionError
          end
        end
      end
    end
  end

  # test for encodings that don't yet (or will never) deal with non-ASCII characters
  def self.generate_ascii_only_case_mapping_tests(encoding)
    all_tests
    # preselect codepoints to speed up testing for small encodings
    codepoints = @@codepoints.select do |code|
      begin
        code.encode(encoding)
        true
      rescue Encoding::UndefinedConversionError
        false
      end
    end
    define_method "test_#{encoding}_upcase" do
      codepoints.each do |code|
        begin
          source = code.encode(encoding) * 5
          target = source.tr 'a-z', 'A-Z'
          result = source.upcase
          assert_equal target, result,
            "from #{code*5} (#{source.dump}) expected #{target.dump} but was #{result.dump}"
        rescue Encoding::UndefinedConversionError
        end
      end
    end
    define_method "test_#{encoding}_downcase" do
      codepoints.each do |code|
        begin
          source = code.encode(encoding) * 5
          target = source.tr 'A-Z', 'a-z'
          result = source.downcase
          assert_equal target, result,
            "from #{code*5} (#{source.dump}) expected #{target.dump} but was #{result.dump}"
        rescue Encoding::UndefinedConversionError
        end
      end
    end
    define_method "test_#{encoding}_capitalize" do
      codepoints.each do |code|
        begin
          source = code.encode(encoding) * 5
          target = source[0].tr('a-z', 'A-Z') + source[1..-1].tr('A-Z', 'a-z')
          result = source.capitalize
          assert_equal target, result,
            "from #{code*5} (#{source.dump}) expected #{target.dump} but was #{result.dump}"
        rescue Encoding::UndefinedConversionError
        end
      end
    end
    define_method "test_#{encoding}_swapcase" do
      codepoints.each do |code|
        begin
          source = code.encode(encoding) * 5
          target = source.tr('a-zA-Z', 'A-Za-z')
          result = source.swapcase
          assert_equal target, result,
            "from #{code*5} (#{source.dump}) expected #{target.dump} but was #{result.dump}"
        rescue Encoding::UndefinedConversionError
        end
      end
    end
  end

  generate_case_mapping_tests 'US-ASCII'
  generate_case_mapping_tests 'ASCII-8BIT'
  generate_case_mapping_tests 'ISO-8859-1'
  generate_case_mapping_tests 'ISO-8859-2'
  generate_case_mapping_tests 'ISO-8859-3'
  generate_case_mapping_tests 'ISO-8859-4'
  generate_case_mapping_tests 'ISO-8859-5'
  generate_case_mapping_tests 'ISO-8859-6'
  generate_case_mapping_tests 'ISO-8859-7'
  generate_case_mapping_tests 'ISO-8859-8'
  generate_case_mapping_tests 'ISO-8859-9'
  generate_case_mapping_tests 'ISO-8859-10'
  generate_case_mapping_tests 'ISO-8859-11'
  generate_case_mapping_tests 'ISO-8859-13'
  generate_case_mapping_tests 'ISO-8859-14'
  generate_case_mapping_tests 'ISO-8859-15'
  generate_case_mapping_tests 'ISO-8859-16'
  generate_ascii_only_case_mapping_tests 'KOI8-R'
  generate_ascii_only_case_mapping_tests 'KOI8-U'
  generate_ascii_only_case_mapping_tests 'Big5'
  generate_ascii_only_case_mapping_tests 'EUC-JP'
  generate_ascii_only_case_mapping_tests 'EUC-KR'
  generate_ascii_only_case_mapping_tests 'GB18030'
  generate_ascii_only_case_mapping_tests 'GB2312'
  generate_ascii_only_case_mapping_tests 'GBK'
  generate_ascii_only_case_mapping_tests 'Shift_JIS'
  generate_ascii_only_case_mapping_tests 'Windows-31J'
  generate_case_mapping_tests 'Windows-1250'
  generate_case_mapping_tests 'Windows-1251'
  generate_case_mapping_tests 'Windows-1252'
  generate_case_mapping_tests 'Windows-1253'
  generate_case_mapping_tests 'Windows-1254'
  generate_case_mapping_tests 'Windows-1255'
  generate_ascii_only_case_mapping_tests 'Windows-1256'
  generate_case_mapping_tests 'Windows-1257'
  generate_unicode_case_mapping_tests 'UTF-8'
  generate_unicode_case_mapping_tests 'UTF-16BE'
  generate_unicode_case_mapping_tests 'UTF-16LE'
  generate_unicode_case_mapping_tests 'UTF-32BE'
  generate_unicode_case_mapping_tests 'UTF-32LE'
end
