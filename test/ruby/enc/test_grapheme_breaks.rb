# frozen_string_literal: true
# Copyright © 2018 Martin J. Dürst (duerst@it.aoyama.ac.jp)

require "test/unit"

class TestGraphemeBreaksFromFile < Test::Unit::TestCase
  class BreakTest
    attr_reader :clusters, :string, :comment, :line_number

    def initialize(line_number, data, comment)
      @line_number = line_number
      @comment = comment
      @clusters = data.sub(/\A\s*÷\s*/, '')
                      .sub(/\s*÷\s*\z/, '')
                      .split(/\s*÷\s*/)
                      .map do |cl|
                        cl.split(/\s*×\s*/)
                          .map do |ch|
                            c = ch.to_i(16)
                             # eliminate cases with surrogates
                            raise ArgumentError if 0xD800 <= c and c <= 0xDFFF
                            c.chr('UTF-8')
                          end.join
                      end
      @string = @clusters.join
    end
  end

  UNICODE_VERSION = RbConfig::CONFIG['UNICODE_VERSION']
  path = File.expand_path("../../../enc/unicode/data/#{UNICODE_VERSION}", __dir__)
  UNICODE_DATA_PATH = File.directory?("#{path}/ucd/auxiliary") ? "#{path}/ucd/auxiliary" : path
  GRAPHEME_BREAK_TEST_FILE = File.expand_path("#{UNICODE_DATA_PATH}/GraphemeBreakTest.txt", __dir__)

  def self.file_available?
    File.exist? GRAPHEME_BREAK_TEST_FILE
  end

  def test_data_files_available
    unless TestGraphemeBreaksFromFile.file_available?
      skip "Unicode data file GraphemeBreakTest not available in #{UNICODE_DATA_PATH}."
    end
  end

  if file_available?
    def read_data
      tests = []
      IO.foreach(GRAPHEME_BREAK_TEST_FILE, encoding: Encoding::UTF_8) do |line|
        if $. == 1 and not line.start_with?("# GraphemeBreakTest-#{UNICODE_VERSION}.txt")
          raise "File Version Mismatch"
        end
        next if /\A#/.match? line
        tests << BreakTest.new($., *line.chomp.split('#')) rescue 'whatever'
      end
      tests
    end

    def all_tests
      @@tests ||= read_data
    rescue Errno::ENOENT
      @@tests ||= []
    end

    def test_each_grapheme_cluster
      all_tests.each do |test|
        expected = test.clusters
        actual = test.string.each_grapheme_cluster.to_a
        assert_equal expected, actual,
          "line #{test.line_number}, expected '#{expected}', " +
          "but got '#{actual}', comment: #{test.comment}"
      end
    end

    def test_backslash_X
      all_tests.each do |test|
        clusters = test.clusters.dup
        string = test.string.dup
        removals = 0
        while string.sub!(/\A\X/, '')
          removals += 1
          clusters.shift
          expected = clusters.join
          assert_equal expected, string,
            "line #{test.line_number}, removals: #{removals}, expected '#{expected}', " +
            "but got '#{string}', comment: #{test.comment}"
        end
        assert_equal expected, string,
          "line #{test.line_number}, after last removal, expected '#{expected}', " +
          "but got '#{string}', comment: #{test.comment}"
      end
    end
  end
end
