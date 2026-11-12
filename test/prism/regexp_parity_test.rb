# frozen_string_literal: true

return unless defined?(RubyVM::InstructionSequence.compile_parsey)

require_relative "test_helper"

module Ruby::Prism
  # Compares the errors and the encoding of regular expressions against CRuby's
  # own parser, which validates a regular expression in the same stages that
  # prism does: it lexes it, checks its encoding modifier, preprocesses its
  # escapes, resolves its encoding, and then parses and compiles its pattern.
  class RegexpParityTest < TestCase
    # Regular expressions whose escapes and characters depend on the encoding of
    # the source, so they are compared in every encoding that is tested.
    ENCODING_CASES = [
      "/a/", "/ą/", "//",

      # Escapes that stand for bytes or code points, and pairs of them.
      *["\\x00", "\\x7F", "\\x80", "\\xFF", "\\u{00}", "\\u{7F}", "\\u{80}", "\\M-\\C-?"].then { |escapes|
        escapes.concat(escapes.product(escapes).map(&:join)).map { |escape| "/#{escape}/" }
      },

      # Escapes and characters that fix the encoding of the regular expression.
      "/\\p{Alpha}/", "/a\\p{Alpha}/", "/\\P{Alpha}/", "/\\p{Alpha}/n",
      "/\\p{Hiragana}/", "/\\p{L}/", "/\\101/", "/\\0/", "/(a)\\1/", "/\\ą/", "/\\ą(/",
      "/\\351/", "/\\343\\201\\202/",
      "/(?<ą>a)/", "/a(?#ą)b/", "/a # ą\nb/x", "/(?x)a # ą\n/", "/a(?#ą)b/u", "/a(?#ą)b/e",

      # Escaped bytes that form characters, or fail to.
      "/\\xE9/", "/\\xE9\\x41/", "/\\xE9A/", "/\\xE9\\d/", "/\\xE9\\n/", "/\\xE9\\101/", "/\\xE9\\u0041/",
      "/\\xC3\\xA9/", "/\\xC3\\x41/", "/\\xA4\\xA2/", "/\\x81\\x30\\x81\\x30/",
      "/\\xED\\xA0\\x80/", "/\\xED\\xB0\\x80/", "/\\xED\\xA4\\xCE\\x71/", "/\\xED\\xA0\\x80\\xED\\xB0\\x80/",
      "/\\xED\\xA0\\x80\\xED\\xB0/", "/\\x81\\x30/", "/\\x81\\x30\\x81/", "/\\x8F\\xA1/", "/\\x8E\\xA1\\xA1/", "/\\x9C\\xF0\\xA0/",
      "/\\M-a/", "/\\M-$\\M-\"/", "/\\M-\\\\/", "/\\c\\M-\\xFE/", "/\\cA\\M-a/", "/\\C-a/", "/\\xE9\\M-a/",
      "/\\x80\\p{L}/", "/\\xE9\\p{Hiragana}/",
      "/(?<a\\xFF>x)/", "/(?#\\xFF/", "/(?#\\xFF)/", "/[\\xFF]/", "/a # \\xFF\nb/x",

      # Characters that are invalid in the encoding of the source.
      "/a\xFFb/", "/\\\xFF/", "/a\xED\xA0\x80b/", "/a\xED\xB0\x80b/", "/a(?#\xFF)b/", "/a # \xFF\nb/x", "/(?<a\xFF>b)/", "/[\xFF]/",
      "/\xFF[a/", "/)\xFFa/", "/(\xFFa/", "/(?#\xFF)[a/", "/[a\xFF\xFF/", "/[a\xFF/", "/)\xFF/",
      "/a\xFF\#{1}b/", "/\#{1}a\xED\xA0\x80b/", "/[\xFF\#{1}]/",

      # Bytes and escapes in the content that the lexer cannot read.
      "/(\\x/", "/(\xFF/", "/\\x(/", "/é\\xZa/e", "/é\xFFa/e", "/a\xFF\\xZ(/", "/a\\xZb\xFFc(/",
      "/a\\\xFFb(/", "/\xE3\x81(/", "/\\u{\xFF}(/", "/\\u{a\xFFb}(/", "/\\u{41 \xFF}/x",

      # Encoding modifiers.
      *[
        "abc", "garçon", "\\x80", "gar\\xC3\\xA7on", "gar\\u{E7}on", "abc\\u{FFFFFF}",
        "\\x80\\u{80}", "\\p{L}", "garçon\\xC3\\xA7", "\\xC3\\xA7garçon", "é(", "é\\xFF("
      ].product(["n", "u", "e", "s"]).map { |source, modifier| "/#{source}/#{modifier}" },
      "/\\xA4\\xA2\\p{L}/e", "/é\\p{L}/e", "/\\p{Hiragana}(?#é)/n", "/é[a/e", "/é[a/n",

      # Escapes for code points.
      "/\\u{D800}/", "/\\u{110000}/", "/\\u{1234567}/", "/\\u{zz}/", "/\\uzz/", "/\\u{110000}[a/",
      "/\\u3042\\xE3/", "/\\u{E9}\\xE9[a/", "/\\u3042\\xDC\\p{Hiragana}/",
      "/a(?#\\u{1234567})b/", "/a # \\u{1234567}\nb/x", "/a(?#\\uzz)b/", "/a # \\u{zz}\nb/x",

      # Errors in escapes come before errors in the pattern.
      "/\\xE9[a/", "/\\xC3\\d[a/", "/\\xE9(/", "/\\xFF[a/n", "/\\p{Hiragana}[a/", "/)\\p{Hiragana}/",

      # Literal fragments of a regular expression with interpolation.
      "/\\xFF\#{1}/", "/a\#{1}\\xE3\\x81/", "/\\u{3042}\#{1}\\xE3\\x81\\x82/", "/é\#{1}/n", "/é\#{1}/e",
      "/\\xE3\#{1}\\x81\\x82/", "/\\M-a\#{1}/", "/\\xE3\#{\"\\x81\\x82\"}/", "/a # \\xFF\n\#{1}/x", "/a(?#\\xFF)\#{1}/"
    ].freeze

    # Regular expressions whose errors are in their pattern, which are compared
    # in fewer encodings since the pattern is parsed the same way in each.
    PATTERN_CASES = [
      # Valid patterns.
      "/(?<a>x)\\k<a>/", "/(a)\\1/", "/(?<a>x)\\g<a>/", "/(a)\\g<1>/", "/[a-z&&[^aeiou]]/", "/(?x) a # c\n/",
      "/\\h\\R\\X/", "/(?>a)/", "/a{,3}/", "/a{2,}/", "/a{2}{3}/", "/(?~a)/", "/\\k<1>(a)/", "/(?<a>x)(?<a>y)\\k<a>/",
      "/(?i-m:a)/", "/(?i)a/", "/[[:alpha:]]/", "/\\p{Foo}\#{1}/", "/(\#{1}/", "/a(?\\!x)\#{1}/",

      # Escaped characters that the lexer removes from the content.
      "/(?\\!x)/", "/\\あ(/", "/a\\/b(/", "/\\\nx(/", "/\\xE3\\x81\\x82(/", "/\\343\\201\\202(/", "%r{(?\\}x)}",

      # Errors in the pattern.
      "/[]/", "/*/", "/+/", "/?/", "/(?<>a)/", "/(/", "/(|/", "/(?</", "/(?/", "/(?#/", "/(?P/", "/)/",
      "/[a/", "/[[a]/", "/[a\\]/", "/a(/x", "/(?x)a # \\xFF\n(/",
      "/a{3,2}/", "/x{100001}/", "/x{1,100001}/",
      "/[b-a]/", "/[a-\\d]/", "/[\\d-a]/",
      "/(?<1a>x)/", "/(?<a-b>x)/", "/\\A*/", "/(?i-/", "/(?i/", "/(?z)/",
      "/\\p{^Alpha/", "/\\p{Alpha/", "/\\p/", "/\\p{}/", "/[[:foo:]]/",
      "/(?(1)a|b|c)/", "/a\#{\"b\"}(/",

      # Names and numbers that do not resolve.
      "/\\k<b>/", "/\\k<a>(?<a>x)/", "/(?<a>x)\\k<b>/", "/\\k<0>/", "/(?<b>x)\\k<1>/",
      "/\\g<b>/", "/(?<a>x)\\g<b>/", "/\\g<2>(a)/", "/(?<a>x)(?<a>y)\\g<a>/",
      "/(a)(?<b>x)\\1/", "/(a)(?<b>x)\\g<1>/",

      # Malformed escapes that the lexer reports.
      "/\\x/", "/\\x(/", "/\\M-\\x(/", "/(\\xZ/", "/a\\xZb/",

      # Errors in the content of a regular expression that is matched with =~,
      # which is validated where its named captures are found.
      "/(\\xZ/ =~ \"\"", "/(\xFFa/ =~ \"\""
    ].freeze

    # Regular expressions where prism does not yet match CRuby. Each one is
    # removed when the stage that it belongs to matches.
    KNOWN_FAILURES = [
      # The literal parts of a regular expression with interpolation are checked
      # and preprocessed.
      "/\\xFF\#{1}/", "/a\#{1}\\xE3\\x81/", "/\\u{3042}\#{1}\\xE3\\x81\\x82/", "/é\#{1}/n",
      "/é\#{1}/e", "/\\xE3\#{1}\\x81\\x82/", "/\\M-a\#{1}/", "/\\xE3\#{\"\\x81\\x82\"}/",
      "/a # \\xFF\n\#{1}/x", "/a\#{\"b\"}(/",

      # Errors in the pattern.
      "/(?#\\xFF/", "/\xFF[a/", "/(?#\xFF)[a/", "/[a\xFF\xFF/",
      "/[a\xFF/", "/é[a/e", "/é[a/n", "/\\xE9[a/",
      "/\\xC3\\d[a/", "/\\xFF[a/n", "/[a/", "/[[a]/",
      "/[a\\]/", "/a{3,2}/", "/x{100001}/", "/x{1,100001}/",
      "/[b-a]/", "/[a-\\d]/", "/[\\d-a]/", "/(?<1a>x)/",
      "/(?i-/", "/(?i/", "/[[:foo:]]/", "/(?(1)a|b|c)/",
      "/\\k<b>/", "/\\k<a>(?<a>x)/", "/(?<a>x)\\k<b>/", "/\\k<0>/",

      # Property escapes are checked against the encoding of the pattern.
      "/\\p{Hiragana}/", "/\\p{L}/", "/\\x80\\p{L}/", "/\\xE9\\p{Hiragana}/",
      "/\\p{Hiragana}[a/", "/\\p{^Alpha/", "/\\p{Alpha/", "/\\p{}/",

      # Names and numbers of groups are resolved once the pattern is parsed.
      "/(?<b>x)\\k<1>/", "/\\g<b>/", "/(?<a>x)\\g<b>/", "/\\g<2>(a)/",
      "/(?<a>x)(?<a>y)\\g<a>/", "/(a)(?<b>x)\\1/", "/(a)(?<b>x)\\g<1>/",

      # Errors in the pattern are followed by the regular expression, as CRuby
      # writes them.
      "/\\ą(/", "/)\xFFa/", "/(\xFFa/", "/)\xFF/",
      "/(\\x/", "/(\xFF/", "/a\\\xFFb(/", "/\xE3\x81(/",
      "/\\u{\xFF}(/", "/\\u{a\xFFb}(/", "/\\u{41 \xFF}/x", "/garçon/n",
      "/garçon\\xC3\\xA7/n", "/\\xC3\\xA7garçon/n", "/é(/n", "/é(/u",
      "/é(/e", "/é(/s", "/é\\xFF(/n", "/é\\xFF(/u",
      "/é\\xFF(/e", "/é\\xFF(/s", "/\\p{Hiragana}(?#é)/n", "/\\xE9(/",
      "/)\\p{Hiragana}/", "/(?\\!x)/", "/\\あ(/", "/a\\/b(/",
      "/\\\nx(/", "/\\xE3\\x81\\x82(/", "/\\343\\201\\202(/", "%r{(?\\}x)}",
      "/[]/", "/*/", "/+/", "/?/",
      "/(?<>a)/", "/(/", "/(|/", "/(?</",
      "/(?/", "/(?#/", "/(?P/", "/)/",
      "/a(/x", "/(?x)a # \\xFF\n(/", "/(?z)/", "/\\M-\\x(/",
      "/(\xFFa/ =~ \"\""
    ].freeze

    # The encodings that ENCODING_CASES are compared in by default, which have
    # characters of one byte, of two bytes, and of up to four and six bytes.
    ENCODINGS = [
      Encoding::UTF_8, Encoding::US_ASCII, Encoding::ASCII_8BIT, Encoding::Windows_1253, Encoding::EUC_JP,
      Encoding::Windows_31J, Encoding::GB18030, Encoding::Big5, Encoding::CESU_8
    ].freeze

    # The encodings that PATTERN_CASES are compared in by default.
    PATTERN_ENCODINGS = [Encoding::UTF_8, Encoding::US_ASCII, Encoding::ASCII_8BIT].freeze

    def test_encoding_cases
      assert_parity(ENCODING_CASES, self.class.each_encoding(ENCODINGS).to_a)
    end

    def test_pattern_cases
      assert_parity(PATTERN_CASES, self.class.each_encoding(PATTERN_ENCODINGS).to_a)
    end

    def test_known_failures_are_cases
      assert_empty KNOWN_FAILURES - ENCODING_CASES - PATTERN_CASES
    end

    private

    # What a parser makes of a regular expression: the messages of the errors
    # that it reports, and the encoding that it gives the regular expression if
    # there are none. The encoding of a regular expression with interpolation
    # depends on the values that are interpolated, so it is not compared.
    Result = Struct.new(:errors, :encoding) do
      # Whether this result of prism's matches the given result of parse.y's.
      # Ruby::Prism keeps validating after an error, so it may report extra errors as
      # long as it reports each one that parse.y does. Where parse.y reports
      # none, prism must report none and give the same encoding.
      def matches?(expected)
        return self == expected if expected.errors.empty?
        expected.errors.tally.all? { |message, count| errors.count(message) >= count }
      end

      def to_s
        errors.empty? ? "encoding #{encoding&.name || "not compared"}" : "errors #{errors.inspect}"
      end
    end

    # Messages of errors in escapes that are shared with strings, which prism
    # words differently from CRuby in every kind of literal.
    LEXER_MESSAGES = {
      "invalid hex escape sequence" => "invalid hex escape"
    }.freeze

    def assert_parity(cases, encodings)
      unexpected_failures = []
      unexpected_passes = []

      cases.each do |regexp|
        mismatches = encodings.filter_map do |encoding|
          source = "# encoding: #{encoding.name}\n#{regexp}".b
          expected = parsey_result(source)
          actual = prism_result(source)
          next if actual.matches?(expected)

          "  #{encoding.name}:\n    parse.y: #{expected}\n    prism:   #{actual}"
        end

        if KNOWN_FAILURES.include?(regexp)
          unexpected_passes << regexp if mismatches.empty?
        elsif mismatches.any?
          unexpected_failures << "#{regexp.inspect}\n#{mismatches.first(3).join("\n")}"
        end
      end

      assert_empty unexpected_failures, "Regular expressions that do not match CRuby:\n#{unexpected_failures.join("\n")}"

      # A known failure may fail in only some encodings, so it is only known to
      # match CRuby once it is compared in every encoding.
      if self.class.all_encodings? && !ENV["PRISM_BUILD_MINIMAL"]
        assert_empty unexpected_passes, "Regular expressions that now match CRuby, to remove from KNOWN_FAILURES:\n#{unexpected_passes.map(&:inspect).join("\n")}"
      end
    end

    def parsey_result(source)
      iseq = RubyVM::InstructionSequence.compile_parsey(source)
      Result.new([], interpolated?(source) ? nil : iseq.eval.encoding)
    rescue SyntaxError => error
      # The message is split as bytes, since the line of source that follows an
      # error from the lexer may hold bytes that are invalid in its encoding.
      encoding = error.message.encoding
      errors =
        error.message.b.split(/\n(?=<compiled>:\d+: )/n).map do |message|
          # Errors from the lexer are followed by the line of source that they
          # are on and a caret that points into it.
          message.sub(/\A<compiled>:\d+: /n, "").sub(/\n[^\n]*\n *\^~*\n?\z/n, "").force_encoding(encoding)
        end

      Result.new(errors, nil)
    end

    def prism_result(source)
      result = Ruby::Prism.parse(source)

      if result.failure?
        errors = result.errors.map { |error| LEXER_MESSAGES.fetch(error.message, error.message) }
        Result.new(errors, nil)
      else
        Result.new([], interpolated?(source) ? nil : result.statement.encoding)
      end
    end

    def interpolated?(source)
      source.include?("\#{")
    end
  end
end
