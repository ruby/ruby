# frozen_string_literal: true

require "ruby/prism"
require "pp"
require "stringio"
require "test/unit"
require "tempfile"

puts "Using prism backend: #{Ruby::Prism::BACKEND}" if ENV["PRISM_FFI_BACKEND"]

# It is useful to have a diff even if the strings to compare are big
# However, ruby/ruby does not have a version of Test::Unit with access to
# max_diff_target_string_size
if defined?(Test::Unit::Assertions::AssertionMessage)
  Test::Unit::Assertions::AssertionMessage.max_diff_target_string_size = 5000
end

module Ruby::Prism
  # A convenience method for retrieving the first statement in the source string
  # parsed by Ruby::Prism.
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
      BASE = ENV.fetch("FIXTURE_BASE", File.join(__dir__, "fixtures"))

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
        File.join(File.expand_path("../..", __dir__), "snapshots", path)
      end

      def test_name(version = nil)
        if version
          :"test_#{version}_#{path}"
        else
          :"test_#{path}"
        end
      end

      def self.each(except: [], &block)
        glob_pattern = ENV.fetch("FOCUS") { custom_base_path? ? File.join("**", "*.rb") : File.join("**", "*.txt") }
        paths = Dir[glob_pattern, base: BASE] - except
        paths.each { |path| yield Fixture.new(path) }
      end

      def self.each_for_version(except: [], version:, &block)
        each(except: except) do |fixture|
          next unless TestCase.ruby_versions_for(fixture.path).include?(version)
          yield fixture
        end
      end

      def self.each_for_current_ruby(except: [], &block)
        each_for_version(except: except, version: CURRENT_MAJOR_MINOR, &block)
      end

      def self.each_with_all_versions(except: [], &block)
        each(except: except) do |fixture|
          TestCase.ruby_versions_for(fixture.path).each do |version|
            yield fixture, version
          end
        end
      end

      def self.custom_base_path?
        ENV.key?("FIXTURE_BASE")
      end
    end

    # Each encoding that prism supports, with the kind of characters that it has,
    # which decides the codepoints that are tested in it.
    ENCODINGS = {
      Encoding::ASCII_8BIT => :single_byte,
      Encoding::US_ASCII => :single_byte,
      Encoding::Windows_1253 => :single_byte,
      Encoding::CP850 => :single_byte,
      Encoding::CP852 => :single_byte,
      Encoding::CP855 => :single_byte,
      Encoding::GB1988 => :single_byte,
      Encoding::IBM437 => :single_byte,
      Encoding::IBM720 => :single_byte,
      Encoding::IBM737 => :single_byte,
      Encoding::IBM775 => :single_byte,
      Encoding::IBM852 => :single_byte,
      Encoding::IBM855 => :single_byte,
      Encoding::IBM857 => :single_byte,
      Encoding::IBM860 => :single_byte,
      Encoding::IBM861 => :single_byte,
      Encoding::IBM862 => :single_byte,
      Encoding::IBM863 => :single_byte,
      Encoding::IBM864 => :single_byte,
      Encoding::IBM865 => :single_byte,
      Encoding::IBM866 => :single_byte,
      Encoding::IBM869 => :single_byte,
      Encoding::ISO_8859_1 => :single_byte,
      Encoding::ISO_8859_2 => :single_byte,
      Encoding::ISO_8859_3 => :single_byte,
      Encoding::ISO_8859_4 => :single_byte,
      Encoding::ISO_8859_5 => :single_byte,
      Encoding::ISO_8859_6 => :single_byte,
      Encoding::ISO_8859_7 => :single_byte,
      Encoding::ISO_8859_8 => :single_byte,
      Encoding::ISO_8859_9 => :single_byte,
      Encoding::ISO_8859_10 => :single_byte,
      Encoding::ISO_8859_11 => :single_byte,
      Encoding::ISO_8859_13 => :single_byte,
      Encoding::ISO_8859_14 => :single_byte,
      Encoding::ISO_8859_15 => :single_byte,
      Encoding::ISO_8859_16 => :single_byte,
      Encoding::KOI8_R => :single_byte,
      Encoding::KOI8_U => :single_byte,
      Encoding::MACCENTEURO => :single_byte,
      Encoding::MACCROATIAN => :single_byte,
      Encoding::MACCYRILLIC => :single_byte,
      Encoding::MACGREEK => :single_byte,
      Encoding::MACICELAND => :single_byte,
      Encoding::MACROMAN => :single_byte,
      Encoding::MACROMANIA => :single_byte,
      Encoding::MACTHAI => :single_byte,
      Encoding::MACTURKISH => :single_byte,
      Encoding::MACUKRAINE => :single_byte,
      Encoding::TIS_620 => :single_byte,
      Encoding::Windows_1250 => :single_byte,
      Encoding::Windows_1251 => :single_byte,
      Encoding::Windows_1252 => :single_byte,
      Encoding::Windows_1254 => :single_byte,
      Encoding::Windows_1255 => :single_byte,
      Encoding::Windows_1256 => :single_byte,
      Encoding::Windows_1257 => :single_byte,
      Encoding::Windows_1258 => :single_byte,
      Encoding::Windows_874 => :single_byte,
      Encoding::Big5 => :double_byte,
      Encoding::Big5_HKSCS => :double_byte,
      Encoding::Big5_UAO => :double_byte,
      Encoding::CP949 => :double_byte,
      Encoding::CP950 => :double_byte,
      Encoding::CP951 => :double_byte,
      Encoding::EUC_KR => :double_byte,
      Encoding::GBK => :double_byte,
      Encoding::GB12345 => :double_byte,
      Encoding::GB2312 => :double_byte,
      Encoding::MACJAPANESE => :double_byte,
      Encoding::Shift_JIS => :double_byte,
      Encoding::SJIS_DoCoMo => :double_byte,
      Encoding::SJIS_KDDI => :double_byte,
      Encoding::SJIS_SoftBank => :double_byte,
      Encoding::Windows_31J => :double_byte,
      Encoding::UTF_8 => :unicode,
      Encoding::UTF8_MAC => :unicode,
      Encoding::UTF8_DoCoMo => :unicode,
      Encoding::UTF8_KDDI => :unicode,
      Encoding::UTF8_SoftBank => :unicode,
      Encoding::CESU_8 => :unicode,
      Encoding::CP51932 => :euc_jp,
      Encoding::EUC_JP => :euc_jp,
      Encoding::EUCJP_MS => :euc_jp,
      Encoding::EUC_JIS_2004 => :euc_jp,
      Encoding::EMACS_MULE => :emacs_mule,
      Encoding::STATELESS_ISO_2022_JP => :emacs_mule,
      Encoding::STATELESS_ISO_2022_JP_KDDI => :emacs_mule,
      Encoding::GB18030 => :gb18030,
      Encoding::EUC_TW => :euc_tw
    }.freeze

    # The encodings that a minimal build supports, which excludes the full set of
    # encodings.
    MINIMAL_ENCODINGS = [
      Encoding::UTF_8, Encoding::US_ASCII, Encoding::ASCII_8BIT, Encoding::EUC_JP, Encoding::Windows_31J
    ].freeze

    # The encodings that are tested by default. Testing every codepoint in an
    # encoding takes a long time, so only a few are tested unless
    # PRISM_TEST_ALL_ENCODINGS is set.
    DEFAULT_ENCODINGS = [Encoding::ASCII_8BIT, Encoding::US_ASCII, Encoding::Windows_1253].freeze

    # Yield each encoding that we want to test, which is each of the given
    # encodings, or every encoding that prism supports if
    # PRISM_TEST_ALL_ENCODINGS is set. A minimal build is only tested in the
    # encodings that it supports.
    def self.each_encoding(defaults = DEFAULT_ENCODINGS, &block)
      return enum_for(__method__, defaults) unless block

      encodings = all_encodings? ? ENCODINGS.keys : defaults
      encodings &= MINIMAL_ENCODINGS if ENV["PRISM_BUILD_MINIMAL"]
      encodings.each(&block)
    end

    # True if every encoding that the build supports is tested.
    def self.all_encodings?
      !!ENV["PRISM_TEST_ALL_ENCODINGS"]
    end

    # Return the codepoints that are tested in the given encoding.
    def self.encoding_codepoints(encoding)
      case ENCODINGS.fetch(encoding)
      when :single_byte
        0...0x100
      when :double_byte
        0...0x10000
      when :unicode
        0...0x110000
      when :euc_jp
        [
          *(0...0x10000),
          *(0...0x10000).map { |bytes| bytes | 0x8F0000 }
        ]
      when :emacs_mule
        [
          *(0...0x80),
          *((0x81...0x90).flat_map { |byte1| (0x90...0x100).map { |byte2| byte1 << 8 | byte2 } }),
          *((0x90...0x9C).flat_map { |byte1| (0xA0...0x100).flat_map { |byte2| (0xA0...0x100).flat_map { |byte3| byte1 << 16 | byte2 << 8 | byte3 } } }),
          *((0xF0...0xF5).flat_map { |byte2| (0xA0...0x100).flat_map { |byte3| (0xA0...0x100).flat_map { |byte4| 0x9C << 24 | byte2 << 16 | byte3 << 8 | byte4 } } }),
        ]
      when :gb18030
        [
          *(0...0x80),
          *((0x81..0xFE).flat_map { |byte1| (0x40...0x100).map { |byte2| byte1 << 8 | byte2 } }),
          *((0x81..0xFE).flat_map { |byte1| (0x30...0x40).flat_map { |byte2| (0x81..0xFE).flat_map { |byte3| (0x2F...0x41).map { |byte4| byte1 << 24 | byte2 << 16 | byte3 << 8 | byte4 } } } }),
        ]
      when :euc_tw
        [
          *(0..0x7F),
          *(0xA1..0xFF).flat_map { |byte1| (0xA1..0xFF).map { |byte2| (byte1 << 8) | byte2 } },
          *(0xA1..0xB0).flat_map { |byte2| (0xA1..0xFF).flat_map { |byte3| (0xA1..0xFF).flat_map { |byte4| 0x8E << 24 | byte2 << 16 | byte3 << 8 | byte4 } } }
        ]
      end
    end

    # True if the current platform is Windows.
    def self.windows?
      RbConfig::CONFIG["host_os"].match?(/cygwin|mingw|mswin/i)
    end

    # All versions that prism can parse
    SYNTAX_VERSIONS = %w[3.3 3.4 4.0 4.1]

    # `RUBY_VERSION` with the patch version excluded
    CURRENT_MAJOR_MINOR = RUBY_VERSION.split(".")[0, 2].join(".")

    # Returns an array of ruby versions that a given filepath should test against:
    # test.txt         # => all available versions
    # 3.4/test.txt     # => versions since 3.4 (inclusive)
    # 3.4-4.2/test.txt # => verisions since 3.4 (inclusive) up to 4.2 (inclusive)
    def self.ruby_versions_for(filepath)
      return [ENV['SYNTAX_VERSION']] if ENV['SYNTAX_VERSION']

      parts = filepath.split("/")
      return SYNTAX_VERSIONS if parts.size == 1

      version_start, version_stop = parts[0].split("-")
      if version_stop
        SYNTAX_VERSIONS[SYNTAX_VERSIONS.index(version_start)..SYNTAX_VERSIONS.index(version_stop)]
      else
        SYNTAX_VERSIONS[SYNTAX_VERSIONS.index(version_start)..]
      end
    end

    if RUBY_VERSION >= "3.3.0"
      def test_all_syntax_versions_present
        assert_include(SYNTAX_VERSIONS, CURRENT_MAJOR_MINOR)
      end
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

    def capture_warnings
      $stderr = StringIO.new
      yield
      $stderr.string
    ensure
      $stderr = STDERR
    end

    def ignore_warnings
      capture_warnings { return yield }
    end
  end
end
