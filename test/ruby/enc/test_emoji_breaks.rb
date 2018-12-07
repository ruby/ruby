# frozen_string_literal: true
# Copyright © 2018 Martin J. Dürst (duerst@it.aoyama.ac.jp)

require "test/unit"

class BreakTest
  attr_reader :string, :comment, :filename, :line_number, :type, :shortname

  def initialize (filename, line_number, data, comment='')
    @filename = filename
    @line_number = line_number
    @comment = comment.gsub(/\s+/, ' ').strip
    if filename=='emoji-test'
      codes, @type = data.split(/\s*;\s*/)
      @shortname = ''
    else
      codes, @type, @shortname = data.split(/\s*;\s*/)
    end
    @type = @type.gsub(/\s+/, ' ').strip
    @shortname = @shortname.gsub(/\s+/, ' ').strip
    @string = codes.split(/\s+/)
                   .map do |ch|
                          c = ch.to_i(16)
                           # eliminate cases with surrogates
                          # raise ArgumentError if 0xD800 <= c and c <= 0xDFFF
                          c.chr('UTF-8')
                        end.join
  end
end

class TestEmojiBreaks < Test::Unit::TestCase
  EMOJI_DATA_FILES = %w[emoji-sequences emoji-test emoji-variation-sequences emoji-zwj-sequences]
  EMOJI_VERSION = RbConfig::CONFIG['UNICODE_EMOJI_VERSION']
  EMOJI_DATA_PATH = File.expand_path("../../../enc/unicode/data/emoji/#{EMOJI_VERSION}", __dir__)

  def self.expand_filename(basename)
    File.expand_path("#{EMOJI_DATA_PATH}/#{basename}.txt", __dir__)
  end

  def self.data_files_available?
    EMOJI_DATA_FILES.all? do |f|
      File.exist?(expand_filename(f))
    end
  end

  def test_data_files_available
    unless TestEmojiBreaks.data_files_available?
      skip "Emoji data files not available in #{EMOJI_DATA_PATH}."
    end
  end
end

TestEmojiBreaks.data_files_available? and  class TestEmojiBreaks
  def read_data
    tests = []
    EMOJI_DATA_FILES.each do |filename|
      version_mismatch = true
      file_tests = []
      IO.foreach(TestEmojiBreaks.expand_filename(filename), encoding: Encoding::UTF_8) do |line|
        line.chomp!
        raise "File Name Mismatch"  if $.==1 and not line=="# #{filename}.txt"
        version_mismatch = false  if line=="# Version: #{EMOJI_VERSION}"
        next  if /\A(#|\z)/.match? line
        file_tests << BreakTest.new(filename, $., *line.split('#')) rescue 'whatever'
      end
      raise "File Version Mismatch"  if version_mismatch
      tests += file_tests
    end
    tests
  end

  def all_tests
    @@tests ||= read_data
  rescue Errno::ENOENT
    @@tests ||= []
  end

  def test_single_emoji
    all_tests.each do |test|
      expected = [test.string]
      actual = test.string.each_grapheme_cluster.to_a
      assert_equal expected, actual,
        "file: #{test.filename}, line #{test.line_number}, " +
        "type: #{test.type}, shortname: #{test.shortname}, comment: #{test.comment}"
    end
  end

  def test_embedded_emoji
    all_tests.each do |test|
      expected = ["\t", test.string, "\t"]
      actual = "\t#{test.string}\t".each_grapheme_cluster.to_a
      assert_equal expected, actual,
        "file: #{test.filename}, line #{test.line_number}, " +
        "type: #{test.type}, shortname: #{test.shortname}, comment: #{test.comment}"
    end
  end

  # test some pseodorandom combinations of emoji
  def test_mixed_emoji
    srand 0
    length = all_tests.length
    step =  503 # use a prime number
    all_tests.each do |test1|
      start = rand step
      start.step(by: step, to: length-1) do |t2|
        test2 = all_tests[t2]
        # exclude skin tones, because they glue to previous grapheme clusters
        next  if (0x1F3FB..0x1F3FF).include? test2.string.ord
        expected = [test1.string, test2.string]
        actual = (test1.string+test2.string).each_grapheme_cluster.to_a
        assert_equal expected, actual,
          "file1: #{test1.filename}, line1 #{test1.line_number}, " +
          "file2: #{test2.filename}, line2 #{test2.line_number},\n" +
          "type1: #{test1.type}, shortname1: #{test1.shortname}, comment1: #{test1.comment},\n" +
          "type2: #{test2.type}, shortname2: #{test2.shortname}, comment2: #{test2.comment}"
      end
    end
  end
end
