# frozen_string_literal: true

require "prism"
require "pp"
require "ripper"
require "stringio"
require "test/unit"
require "tempfile"

puts "Using prism backend: #{Prism::BACKEND}" if ENV["PRISM_FFI_BACKEND"]

# It is useful to have a diff even if the strings to compare are big
# However, ruby/ruby does not have a version of Test::Unit with access to
# max_diff_target_string_size
if defined?(Test::Unit::Assertions::AssertionMessage)
  Test::Unit::Assertions::AssertionMessage.max_diff_target_string_size = 5000
end

module Prism
  # A convenience method for retrieving the first statement in the source string
  # parsed by Prism.
  def self.parse_statement(source, **options)
    parse(source, **options).value.statements.body.first
  end

  class ParseResult < Result
    # Returns the first statement in the body of the parsed source.
    def statement
      value.statements.body.first
    end
  end

  class TestCase < ::Test::Unit::TestCase
    # We have a set of fixtures that we use to test various aspects of the
    # parser. They are all represented as .txt files under the
    # test/prism/fixtures directory. Typically in test files you will find calls
    # to Fixture.each which yields Fixture objects to the given block. These
    # are used to define test methods that assert against each fixture in some
    # way.
    class Fixture
      BASE = File.join(__dir__, "fixtures")

      attr_reader :path

      def initialize(path)
        @path = path
      end

      def read
        File.read(full_path, binmode: true, external_encoding: Encoding::UTF_8)
      end

      def full_path
        File.join(BASE, path)
      end

      def snapshot_path
        File.join(__dir__, "snapshots", path)
      end

      def test_name
        :"test_#{path}"
      end

      def self.each(except: [], &block)
        paths = Dir[ENV.fetch("FOCUS") { File.join("**", "*.txt") }, base: BASE] - except
        paths.each { |path| yield Fixture.new(path) }
      end
    end

    # Yield each encoding that we want to test, along with a range of the
    # codepoints that should be tested.
    def self.each_encoding
      codepoints_1byte = 0...0x100

      yield Encoding::ASCII_8BIT, codepoints_1byte
      yield Encoding::US_ASCII, codepoints_1byte

      if !ENV["PRISM_BUILD_MINIMAL"]
        yield Encoding::Windows_1253, codepoints_1byte
      end

      # By default we don't test every codepoint in these encodings because it
      # takes a very long time.
      return unless ENV["PRISM_TEST_ALL_ENCODINGS"]

      yield Encoding::CP850, codepoints_1byte
      yield Encoding::CP852, codepoints_1byte
      yield Encoding::CP855, codepoints_1byte
      yield Encoding::GB1988, codepoints_1byte
      yield Encoding::IBM437, codepoints_1byte
      yield Encoding::IBM720, codepoints_1byte
      yield Encoding::IBM737, codepoints_1byte
      yield Encoding::IBM775, codepoints_1byte
      yield Encoding::IBM852, codepoints_1byte
      yield Encoding::IBM855, codepoints_1byte
      yield Encoding::IBM857, codepoints_1byte
      yield Encoding::IBM860, codepoints_1byte
      yield Encoding::IBM861, codepoints_1byte
      yield Encoding::IBM862, codepoints_1byte
      yield Encoding::IBM863, codepoints_1byte
      yield Encoding::IBM864, codepoints_1byte
      yield Encoding::IBM865, codepoints_1byte
      yield Encoding::IBM866, codepoints_1byte
      yield Encoding::IBM869, codepoints_1byte
      yield Encoding::ISO_8859_1, codepoints_1byte
      yield Encoding::ISO_8859_2, codepoints_1byte
      yield Encoding::ISO_8859_3, codepoints_1byte
      yield Encoding::ISO_8859_4, codepoints_1byte
      yield Encoding::ISO_8859_5, codepoints_1byte
      yield Encoding::ISO_8859_6, codepoints_1byte
      yield Encoding::ISO_8859_7, codepoints_1byte
      yield Encoding::ISO_8859_8, codepoints_1byte
      yield Encoding::ISO_8859_9, codepoints_1byte
      yield Encoding::ISO_8859_10, codepoints_1byte
      yield Encoding::ISO_8859_11, codepoints_1byte
      yield Encoding::ISO_8859_13, codepoints_1byte
      yield Encoding::ISO_8859_14, codepoints_1byte
      yield Encoding::ISO_8859_15, codepoints_1byte
      yield Encoding::ISO_8859_16, codepoints_1byte
      yield Encoding::KOI8_R, codepoints_1byte
      yield Encoding::KOI8_U, codepoints_1byte
      yield Encoding::MACCENTEURO, codepoints_1byte
      yield Encoding::MACCROATIAN, codepoints_1byte
      yield Encoding::MACCYRILLIC, codepoints_1byte
      yield Encoding::MACGREEK, codepoints_1byte
      yield Encoding::MACICELAND, codepoints_1byte
      yield Encoding::MACROMAN, codepoints_1byte
      yield Encoding::MACROMANIA, codepoints_1byte
      yield Encoding::MACTHAI, codepoints_1byte
      yield Encoding::MACTURKISH, codepoints_1byte
      yield Encoding::MACUKRAINE, codepoints_1byte
      yield Encoding::TIS_620, codepoints_1byte
      yield Encoding::Windows_1250, codepoints_1byte
      yield Encoding::Windows_1251, codepoints_1byte
      yield Encoding::Windows_1252, codepoints_1byte
      yield Encoding::Windows_1254, codepoints_1byte
      yield Encoding::Windows_1255, codepoints_1byte
      yield Encoding::Windows_1256, codepoints_1byte
      yield Encoding::Windows_1257, codepoints_1byte
      yield Encoding::Windows_1258, codepoints_1byte
      yield Encoding::Windows_874, codepoints_1byte

      codepoints_2bytes = 0...0x10000

      yield Encoding::Big5, codepoints_2bytes
      yield Encoding::Big5_HKSCS, codepoints_2bytes
      yield Encoding::Big5_UAO, codepoints_2bytes
      yield Encoding::CP949, codepoints_2bytes
      yield Encoding::CP950, codepoints_2bytes
      yield Encoding::CP951, codepoints_2bytes
      yield Encoding::EUC_KR, codepoints_2bytes
      yield Encoding::GBK, codepoints_2bytes
      yield Encoding::GB12345, codepoints_2bytes
      yield Encoding::GB2312, codepoints_2bytes
      yield Encoding::MACJAPANESE, codepoints_2bytes
      yield Encoding::Shift_JIS, codepoints_2bytes
      yield Encoding::SJIS_DoCoMo, codepoints_2bytes
      yield Encoding::SJIS_KDDI, codepoints_2bytes
      yield Encoding::SJIS_SoftBank, codepoints_2bytes
      yield Encoding::Windows_31J, codepoints_2bytes

      codepoints_unicode = (0...0x110000)

      yield Encoding::UTF_8, codepoints_unicode
      yield Encoding::UTF8_MAC, codepoints_unicode
      yield Encoding::UTF8_DoCoMo, codepoints_unicode
      yield Encoding::UTF8_KDDI, codepoints_unicode
      yield Encoding::UTF8_SoftBank, codepoints_unicode
      yield Encoding::CESU_8, codepoints_unicode

      codepoints_eucjp = [
        *(0...0x10000),
        *(0...0x10000).map { |bytes| bytes | 0x8F0000 }
      ]

      yield Encoding::CP51932, codepoints_eucjp
      yield Encoding::EUC_JP, codepoints_eucjp
      yield Encoding::EUCJP_MS, codepoints_eucjp
      yield Encoding::EUC_JIS_2004, codepoints_eucjp

      codepoints_emacs_mule = [
        *(0...0x80),
        *((0x81...0x90).flat_map { |byte1| (0x90...0x100).map { |byte2| byte1 << 8 | byte2 } }),
        *((0x90...0x9C).flat_map { |byte1| (0xA0...0x100).flat_map { |byte2| (0xA0...0x100).flat_map { |byte3| byte1 << 16 | byte2 << 8 | byte3 } } }),
        *((0xF0...0xF5).flat_map { |byte2| (0xA0...0x100).flat_map { |byte3| (0xA0...0x100).flat_map { |byte4| 0x9C << 24 | byte3 << 16 | byte3 << 8 | byte4 } } }),
      ]

      yield Encoding::EMACS_MULE, codepoints_emacs_mule
      yield Encoding::STATELESS_ISO_2022_JP, codepoints_emacs_mule
      yield Encoding::STATELESS_ISO_2022_JP_KDDI, codepoints_emacs_mule

      codepoints_gb18030 = [
        *(0...0x80),
        *((0x81..0xFE).flat_map { |byte1| (0x40...0x100).map { |byte2| byte1 << 8 | byte2 } }),
        *((0x81..0xFE).flat_map { |byte1| (0x30...0x40).flat_map { |byte2| (0x81..0xFE).flat_map { |byte3| (0x2F...0x41).map { |byte4| byte1 << 24 | byte2 << 16 | byte3 << 8 | byte4 } } } }),
      ]

      yield Encoding::GB18030, codepoints_gb18030

      codepoints_euc_tw = [
        *(0..0x7F),
        *(0xA1..0xFF).flat_map { |byte1| (0xA1..0xFF).map { |byte2| (byte1 << 8) | byte2 } },
        *(0xA1..0xB0).flat_map { |byte2| (0xA1..0xFF).flat_map { |byte3| (0xA1..0xFF).flat_map { |byte4| 0x8E << 24 | byte2 << 16 | byte3 << 8 | byte4 } } }
      ]

      yield Encoding::EUC_TW, codepoints_euc_tw
    end

    private

    if RUBY_ENGINE == "ruby" && RubyVM::InstructionSequence.compile("").to_a[4][:parser] != :prism
      # Check that the given source is valid syntax by compiling it with RubyVM.
      def check_syntax(source)
        ignore_warnings { RubyVM::InstructionSequence.compile(source) }
      end

      # Assert that the given source is valid Ruby syntax by attempting to
      # compile it, and then implicitly checking that it does not raise an
      # syntax errors.
      def assert_valid_syntax(source)
        check_syntax(source)
      end

      # Refute that the given source is invalid Ruby syntax by attempting to
      # compile it and asserting that it raises a SyntaxError.
      def refute_valid_syntax(source)
        assert_raise(SyntaxError) { check_syntax(source) }
      end
    else
      def assert_valid_syntax(source)
      end

      def refute_valid_syntax(source)
      end
    end

    # CRuby has this same method, so define it so that we don't accidentally
    # break CRuby CI.
    def assert_raises(*args, &block)
      raise "Use assert_raise instead"
    end

    def assert_equal_nodes(expected, actual, compare_location: true, parent: nil)
      assert_equal expected.class, actual.class

      case expected
      when Array
        assert_equal(
          expected.size,
          actual.size,
          -> { "Arrays were different sizes. Parent: #{parent.pretty_inspect}" }
        )

        expected.zip(actual).each do |(expected_element, actual_element)|
          assert_equal_nodes(
            expected_element,
            actual_element,
            compare_location: compare_location,
            parent: actual
          )
        end
      when SourceFileNode
        expected_deconstruct = expected.deconstruct_keys(nil)
        actual_deconstruct = actual.deconstruct_keys(nil)
        assert_equal expected_deconstruct.keys, actual_deconstruct.keys

        # Filepaths can be different if test suites were run on different
        # machines. We accommodate for this by comparing the basenames, and not
        # the absolute filepaths.
        expected_filepath = expected_deconstruct.delete(:filepath)
        actual_filepath = actual_deconstruct.delete(:filepath)

        assert_equal expected_deconstruct, actual_deconstruct
        assert_equal File.basename(expected_filepath), File.basename(actual_filepath)
      when Node
        deconstructed_expected = expected.deconstruct_keys(nil)
        deconstructed_actual = actual.deconstruct_keys(nil)
        assert_equal deconstructed_expected.keys, deconstructed_actual.keys

        deconstructed_expected.each_key do |key|
          assert_equal_nodes(
            deconstructed_expected[key],
            deconstructed_actual[key],
            compare_location: compare_location,
            parent: actual
          )
        end
      when Location
        assert_operator actual.start_offset, :<=, actual.end_offset, -> {
          "start_offset > end_offset for #{actual.inspect}, parent is #{parent.pretty_inspect}"
        }

        if compare_location
          assert_equal(
            expected.start_offset,
            actual.start_offset,
            -> { "Start locations were different. Parent: #{parent.pretty_inspect}" }
          )

          assert_equal(
            expected.end_offset,
            actual.end_offset,
            -> { "End locations were different. Parent: #{parent.pretty_inspect}" }
          )
        end
      else
        assert_equal expected, actual
      end
    end

    def ignore_warnings
      previous = $VERBOSE
      $VERBOSE = nil

      begin
        yield
      ensure
        $VERBOSE = previous
      end
    end
  end
end
