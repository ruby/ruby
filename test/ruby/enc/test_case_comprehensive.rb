# Copyright © 2016 Martin J. Dürst (duerst@it.aoyama.ac.jp)

require "test/unit"
require 'unicode_normalize/normalize'  # only for UNICODE_VERSION

class CaseTest
  attr_reader :method_name, :attributes, :first_data, :follow_data
  def initialize(method_name, attributes, first_data, follow_data=first_data)
    @method_name = method_name
    @attributes  = attributes
    @first_data  = first_data
    @follow_data = follow_data
  end
end

class TestComprehensiveCaseFold < Test::Unit::TestCase
  UNICODE_VERSION = UnicodeNormalize::UNICODE_VERSION
  UNICODE_DATA_PATH = "../../../enc/unicode/data/#{UNICODE_VERSION}"

  def self.hex2utf8(s)
    s.split(' ').map { |c| c.to_i(16) }.pack('U*')
  end

  def self.read_data_file (filename)
    IO.readlines(File.expand_path("#{UNICODE_DATA_PATH}/#{filename}.txt", __dir__), encoding: Encoding::ASCII_8BIT)
    .tap do |lines|
           raise "File Version Mismatch" unless filename=='UnicodeData' or /#{filename}-#{UNICODE_VERSION}\.txt/ =~ lines[0]
         end
    .reject { |line| line =~ /^[\#@]/ or line =~ /^\s*$/ or line =~ /Surrogate/ }
    .each do |line|
      data = line.chomp.split('#')[0].split /;\s*/, 15
      code = data[0].to_i(16).chr('UTF-8')
      yield code, data
    end
  end

  def self.read_data
    @@codepoints = []

    downcase  = Hash.new { |h, c| c }
    upcase    = Hash.new { |h, c| c }
    titlecase = Hash.new { |h, c| c }
    casefold  = Hash.new { |h, c| c }
    turkic_upcase    = Hash.new { |h, c| upcase[c] }
    turkic_downcase  = Hash.new { |h, c| downcase[c] }
    turkic_titlecase = Hash.new { |h, c| titlecase[c] }
    ascii_upcase     = Hash.new { |h, c| c =~ /^[a-zA-Z]$/ ? upcase[c] : c }
    ascii_downcase   = Hash.new { |h, c| c =~ /^[a-zA-Z]$/ ? downcase[c] : c }
    ascii_titlecase  = Hash.new { |h, c| c =~ /^[a-zA-Z]$/ ? titlecase[c] : c }

    read_data_file('UnicodeData') do |code, data|
      @@codepoints << code
      upcase[code] = hex2utf8 data[12] unless data[12].empty?
      downcase[code] = hex2utf8 data[13] unless data[13].empty?
      titlecase[code] = hex2utf8 data[14] unless data[14].empty?
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
      when /^tr\s*/
        if data[4]!='tr After_I'
          turkic_upcase[code] = hex2utf8 data[3]
          turkic_downcase[code] = hex2utf8 data[1]
          turkic_titlecase[code] = hex2utf8 data[2]
        end
      end
    end

    tests = [
      CaseTest.new(:downcase,   [:lithuanian], downcase),
      CaseTest.new(:upcase,     [:lithuanian], upcase),
      CaseTest.new(:capitalize, [:lithuanian], titlecase, downcase),
      # swapcase?????!!!!!
      CaseTest.new(:downcase,   [:fold],       casefold),
      CaseTest.new(:upcase,     [:turkic],     turkic_upcase),
      CaseTest.new(:downcase,   [:turkic],     turkic_downcase),
      CaseTest.new(:capitalize, [:turkic],     turkic_titlecase, turkic_downcase),
      CaseTest.new(:upcase,     [:ascii],      ascii_upcase),
      CaseTest.new(:downcase,   [:ascii],      ascii_downcase),
      CaseTest.new(:capitalize, [:ascii],      ascii_titlecase, ascii_downcase),
    ]
  end

  def self.all_tests
    @@tests ||= read_data
  end

  def self.generate_casefold_tests (encoding)
    all_tests.each do |test|
      attributes = test.attributes.map(&:to_s).join '-'
      attributes.prepend '_' unless attributes.empty?
      define_method "test_#{encoding}_#{test.method_name}#{attributes}" do
        @@codepoints.each do |code|
          begin
            source = code.encode(encoding) * 5
            target = test.first_data[code].encode(encoding) + test.follow_data[code].encode(encoding) * 4
            result = source.send(test.method_name, *test.attributes)
            assert_equal target, result,
              "from #{source} (#{source.dump}) expected #{target.dump} but was #{result.dump}"
          rescue Encoding::UndefinedConversionError
          end
        end
      end
    end
  end

  generate_casefold_tests 'US-ASCII'
  generate_casefold_tests 'ASCII-8BIT'
  generate_casefold_tests 'UTF-8'
end
