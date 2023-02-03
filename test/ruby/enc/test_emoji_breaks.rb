# frozen_string_literal: true
# Copyright © 2018 Martin J. Dürst (duerst@it.aoyama.ac.jp)

require "test/unit"

class TestEmojiBreaks < Test::Unit::TestCase
  class BreakTest
    attr_reader :string, :comment, :filename, :line_number, :type, :shortname

    def initialize(filename, line_number, data, comment='')
      @filename = filename
      @line_number = line_number
      @comment = comment.gsub(/\s+/, ' ').strip
      if filename=='emoji-test' or filename=='emoji-variation-sequences'
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

  class BreakFile
    attr_reader :basename, :fullname, :version
    FILES = []

    def initialize(basename, path, version)
      @basename = basename
      @fullname = "#{path}/#{basename}.txt" # File.expand_path(path + version, __dir__)
      @version  = version
      FILES << self
    end

    def self.files
      FILES
    end
  end

  UNICODE_VERSION   = RbConfig::CONFIG['UNICODE_VERSION']
  UNICODE_DATA_PATH = File.expand_path("../../../enc/unicode/data/#{UNICODE_VERSION}/ucd/emoji", __dir__)
  EMOJI_VERSION     = RbConfig::CONFIG['UNICODE_EMOJI_VERSION']
  EMOJI_DATA_PATH   = File.expand_path("../../../enc/unicode/data/emoji/#{EMOJI_VERSION}", __dir__)

  EMOJI_DATA_FILES  = %w[emoji-sequences emoji-test emoji-zwj-sequences].map do |basename|
    BreakFile.new(basename, EMOJI_DATA_PATH, EMOJI_VERSION)
  end
  UNICODE_DATA_FILE = BreakFile.new('emoji-variation-sequences', UNICODE_DATA_PATH, UNICODE_VERSION)
  EMOJI_DATA_FILES << UNICODE_DATA_FILE

  def self.data_files_available?
    EMOJI_DATA_FILES.all? do |f|
      File.exist?(f.fullname)
    end
  end

  def test_data_files_available
    assert_equal 4, EMOJI_DATA_FILES.size # debugging test
    unless TestEmojiBreaks.data_files_available?
      omit "Emoji data files not available in #{EMOJI_DATA_PATH}."
    end
  end

  if data_files_available?
    def read_data
      tests = []
      EMOJI_DATA_FILES.each do |file|
        version_mismatch = true
        file_tests = []
        IO.foreach(file.fullname, encoding: Encoding::UTF_8) do |line|
          line.chomp!
          if $.==1
            if line=="# #{file.basename}-#{file.version}.txt"
              version_mismatch = false
            elsif line!="# #{file.basename}.txt"
              raise "File Name Mismatch: line: #{line}, expected filename: #{file.basename}.txt"
            end
          end
          version_mismatch = false  if line =~ /^# Version: #{file.version}/                 # 13.0 and older
          version_mismatch = false  if line =~ /^# Used with Emoji Version #{EMOJI_VERSION}/ # 14.0 and newer
          next  if line.match?(/\A(#|\z)/)
          if line =~ /^(\h{4,6})\.\.(\h{4,6}) *(;.+)/  # deal with Unicode ranges in emoji-sequences.txt (Bug #18028)
            range_start = $1.to_i(16)
            range_end   = $2.to_i(16)
            rest        = $3
            (range_start..range_end).each do |code_point|
              file_tests << BreakTest.new(file.basename, $., *(code_point.to_s(16)+rest).split('#', 2))
            end
          else
            file_tests << BreakTest.new(file.basename, $., *line.split('#', 2))
          end
        end
        raise "File Version Mismatch: file: #{file.fullname}, version: #{file.version}"  if version_mismatch
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
end
