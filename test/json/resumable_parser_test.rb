# frozen_string_literal: true
require_relative 'test_helper'

class JSONResumageParserTest < Test::Unit::TestCase
  include JSON

  def setup
    omit "JRuby not supported" if RUBY_ENGINE == "jruby"
    @parser = new_parser
  end

  def test_keyword_arguments
    new_parser
    new_parser({})
    new_parser(allow_nan: true)

    error = assert_raise(ArgumentError) do
      new_parser(doesnt_exist: true, allow_nan: true)
    end
    assert_equal "unknown keyword: doesnt_exist", error.message

    error = assert_raise(ArgumentError) do
      new_parser(doesnt_exist: true, allow_nan: true, a: 1, b: 2)
    end
    assert_equal "unknown keywords: doesnt_exist, a, b", error.message
  end

  def test_value
    refute_predicate @parser, :value?
    assert_raise(ArgumentError) { @parser.value }

    @parser << '[]'

    refute_predicate @parser, :value?
    assert_raise(ArgumentError) { @parser.value }

    assert @parser.parse

    assert_predicate @parser, :value?
    assert_equal [], @parser.value

    refute_predicate @parser, :value?
    assert_raise(ArgumentError) { @parser.value }
  end

  def test_clear
    @parser << '[1, 2, 3'
    refute @parser.parse
    assert_equal '3', @parser.rest

    @parser.clear

    assert_equal '', @parser.rest
    refute_predicate @parser, :value?

    @parser << '[1, 2, 3]['
    assert @parser.parse
    assert_predicate @parser, :value?
    assert_equal '[', @parser.rest

    @parser.clear

    assert_equal '', @parser.rest
    refute_predicate @parser, :value?
  end

  def test_parse_with_empty_buffer_keeps_parser_usable
    # parse before any feed must not leak the in_use lock
    refute @parser.parse
    @parser << '[1, 2, 3]'
    assert @parser.parse
    assert_equal [1, 2, 3], @parser.value

    # same after a clear with no following feed
    @parser.clear
    refute @parser.parse
    @parser << '[4]'
    assert @parser.parse
    assert_equal [4], @parser.value
  end

  def test_clear_resets_nesting_depth
    # An unfinished document leaks a nesting level; #clear must reset it so a later shallow
    # document is not rejected with a spurious NestingError.
    parser = new_parser(max_nesting: 10)
    10.times do
      parser << '[1' # opens an array that is never closed before clear
      parser.parse
      parser.clear
    end
    parser << '[1]'
    assert parser.parse
    assert_equal [1], parser.value
  end

  def test_nested_parse_error
    parser = new_parser(on_load: ->(o) do
      JSON.parse("") #=> raises JSON::ParserError
      o
    end)
    parser << "[1]"

    assert_raise(JSON::ParserError) do
      parser.parse
    end
  end

  def test_parse_document_direct
    @parser << '[true]'
    assert_equal true, @parser.parse
    assert_equal [true], @parser.value
  end

  def test_parse_multiple_documents_direct
    @parser << '[true]{}[1, 2, 3]'

    assert_equal true, @parser.parse
    assert_equal [true], @parser.value

    assert_equal true, @parser.parse
    assert_equal({}, @parser.value)

    assert_equal true, @parser.parse
    assert_equal [1, 2, 3], @parser.value
  end

  def test_parse_top_level_keywords
    assert_resumed_parsing('true')
    assert_resumed_parsing('false')
    assert_resumed_parsing('null')

    assert_parse_stream([true, false, nil], 'truefalsenull')
  end

  def test_parse_top_level_numbers
    assert_parse_stream([1, 2, 3], '1 2 3 ')
    assert_parse_stream([1, 2], '1 2 3') # Parser can't know if the number is terminated
    assert_parse_stream([3], ' ')
    assert_parse_stream([1, 2, 3, true], '1 2 3true')
    assert_parse_stream([-1, 2.34, 5.0e67], '-1 2.34 5e67 ')
  end

  def test_parse_byte_by_byte_array
    assert_resumed_parsing('[]')
    assert_resumed_parsing('[    ]')
    assert_resumed_parsing('[true]')
    assert_resumed_parsing('[12]')
    assert_resumed_parsing('[ 12 ]')
    assert_resumed_parsing('[ 12.3 ]')
    assert_resumed_parsing('[ 12.3e12 ]')
    assert_resumed_parsing('[ 1e12 ]')
    assert_resumed_parsing('[-12]')
    assert_resumed_parsing('[ -12 ]')
    assert_resumed_parsing('[ -12.3 ]')
    assert_resumed_parsing('[ -12.3e12 ]')
    assert_resumed_parsing('[ -1e12 ]')
  end

  def test_parse_byte_by_byte_object
    assert_resumed_parsing('{}')
    assert_resumed_parsing('{    }')
    assert_resumed_parsing('{"test" : true}')
    assert_resumed_parsing('{  "test":12, "value" : { "key": 42}  }')
  end

  def test_parse_byte_by_byte_string
    assert_resumed_parsing(JSON.generate('test'))
    assert_resumed_parsing(JSON.generate('te\\st'))
    assert_resumed_parsing('"te\\u2028st"')
    assert_resumed_parsing(JSON.generate("te\u2028st"))
    assert_resumed_parsing(JSON.generate("te \u2028 st"))
  end

  def test_parse_byte_by_byte_numbers
    assert_resumed_parsing('123 ', trailing_bytes: 1)
  end

  def test_nul_byte_is_a_syntax_error
    # A NUL byte in a structural position must raise, not stall forever waiting for more input
    # (peek() returns 0 both at EOS and for a literal NUL byte).
    assert_parse_error "\x00"           # document value
    assert_parse_error "[\x00]"         # first array element
    assert_parse_error "[1\x00]"        # after an array element (',' or ']' expected)
    assert_parse_error "[1,\x00]"       # array element after ','
    assert_parse_error "{\x00}"         # object key
    assert_parse_error "{\"a\":1\x00}"  # after an object value (',' or '}' expected)
    assert_parse_error "{\"a\":1,\x00}" # object key after ','
  end

  def test_incomplete_input_at_structural_positions_resumes
    # Counterpart of test_nul_byte_is_a_syntax_error: a genuine EOS at the same positions must
    # stay incomplete (return false), not raise -- this is what distinguishes EOS from a NUL.
    assert_incomplete "["
    assert_incomplete "[1"
    assert_incomplete "[1,"
    assert_incomplete "{"
    assert_incomplete "{\"a\""
    assert_incomplete "{\"a\":1"
    assert_incomplete "{\"a\":1,"
  end

  def test_rest
    @parser << '[1, 2, 3, "unterminated string'
    refute @parser.parse
    assert_equal '"unterminated string', @parser.rest
  end

  def test_eos
    assert_predicate @parser, :eos?

    @parser << '[1, 2, 3]'
    refute_predicate @parser, :eos?

    assert @parser.parse
    assert_predicate @parser, :eos?

    @parser << '123'
    refute_predicate @parser, :eos?

    refute @parser.parse
    refute_predicate @parser, :eos?

    @parser << ' '
    assert @parser.parse
    assert_equal 123, @parser.value
    assert_predicate @parser, :eos?

    refute @parser.parse
    assert_predicate @parser, :eos?
  end

  def test_partial_value
    assert_nil @parser.partial_value
    assert_partial_value [1, 2, 3], '[1, 2, 3, "unterminated string'
    assert_partial_value({ "a" => 1, "b" => { "c" => nil } }, '{ "a": 1, "b": { "c": "unterminated string')
    assert_partial_value({ "a" => 1, "b" => { "c" => nil } }, '{ "a": 1, "b": { "c"')
    assert_partial_value([1, { "a" => 1, "b" => { "c" => nil } }], '[1, { "a": 1, "b": { "c"')
  end

  def test_partial_value_issue_1005
    data = <<~JSON
      [
      []
      ]
    JSON
    data.each_line do |line|
      @parser << line
      @parser.parse
      @parser.partial_value # This unexpected parse error doesn't happen if we comment this out
    end
    assert_equal [[]], @parser.value
  end

  def test_partial_value_missing
    assert_nil @parser.partial_value
  end

  def test_reentrency_prevented
    called = false
    parser = nil
    callback = ->(o) do
      unless called
        called = true
        parser.parse
      end
      o
    end
    parser = new_parser(on_load: callback)
    parser << '[]'
    error = assert_raise ArgumentError do
      parser.parse
    end
    assert_equal "ResumableParser can't be used recursively", error.message

    called = false
    parser = nil
    callback = ->(o) do
      unless called
        called = true
        parser.partial_value
      end
      o
    end
    parser = new_parser(on_load: callback)
    parser << '[]'
    error = assert_raise ArgumentError do
      parser.parse
    end
    assert_equal "ResumableParser can't be used recursively", error.message
  end

  def test_reentrency_prevented_in_partial_value
    parser = nil
    callback = ->(o) do
      # Arrays are only built while partial_value runs (the scalars were pushed by the
      # earlier parse); re-entering here used to corrupt/free the shared frame stack.
      parser.parse if o.is_a?(Array)
      o
    end
    parser = new_parser(on_load: callback)
    parser << '[1, [2, 3,'
    parser.parse
    error = assert_raise ArgumentError do
      parser.partial_value
    end
    assert_equal "ResumableParser can't be used recursively", error.message

    # The in_use lock must be released even though partial_value raised.
    refute_predicate parser, :value?
  end

  def test_feed_during_callback_prevented
    parser = nil
    callback = ->(o) do
      parser << '99' if o == 1 # feeding while a parse is running must be rejected
      o
    end
    parser = new_parser(on_load: callback)
    parser << '[1, 2, 3]'
    error = assert_raise ArgumentError do
      parser.parse
    end
    assert_equal "ResumableParser can't be used recursively", error.message

    # the lock is released, so the parser stays usable
    parser = new_parser
    parser << '[1, 2, 3]'
    assert parser.parse
    assert_equal [1, 2, 3], parser.value
  end

  def test_exception_unlock_parser
    called = false
    parser = nil
    callback = ->(o) do
      unless called
        called = true
        raise "oops"
      end
      o
    end
    parser = new_parser(on_load: callback)
    parser << '[][1]'
    assert_raise RuntimeError do
      parser.parse
    end

    assert parser.parse
    assert_equal [1], parser.value
  end

  def test_spill_rvalue_stack
    expected = [1] * 1000
    @parser << JSON.dump(expected)
    assert @parser.parse
    assert_equal expected, @parser.value
  end

  def test_spill_frames_stack
    json = '[' * 1000 + ']' * 1000
    expected = JSON.parse(json, max_nesting: 1000)
    @parser = new_parser(max_nesting: 1000)
    @parser << json
    assert @parser.parse
    assert_equal expected, @parser.value
  end

  def test_buffer_shrink
    doc1 = '{"a":"' + ("x" * 800) + '"} {'   # >= 512 bytes
    doc2 = '"b":1} '

    parser = JSON::ResumableParser.new({})

    parser << doc1 # internal buffer becomes a *shared* string here
    parser.parse # consume doc1 -> >50% of a >=512B buffer is now consumed
    parser.value

    parser << doc2 # buffer is shrinked
    parser.parse
    parser.value
  end

  def test_parsed_bytes
    chunk = '[1, 2, 3, 4, tru'
    @parser << chunk
    refute @parser.parse
    assert_equal chunk.bytesize, @parser.parsed_bytes

    @parser << 'e][]'
    assert @parser.parse
    assert_equal chunk.bytesize + 2, @parser.parsed_bytes

    assert @parser.parse
    assert_equal 2, @parser.parsed_bytes

    @parser << chunk
    refute @parser.parse
    assert_equal chunk.bytesize, @parser.parsed_bytes
    @parser.clear
    assert_equal 0, @parser.parsed_bytes
  end

  def test_parse_error_message
    error = assert_parse_error("\n\n[plop\nfoo", "unexpected character: 'plop'")
    assert_equal 0, error.line
    assert_equal 0, error.column
  end

  private

  def assert_parse_error(json, expected_error_message = nil)
    parser = new_parser
    parser << json
    error = assert_raise(JSON::ParserError, "expected a parse error for #{json.inspect}") do
      parser.parse
    end
    if expected_error_message
      assert_equal expected_error_message, error.message
    end
    error
  end

  def assert_incomplete(json)
    parser = new_parser
    parser << json
    refute(parser.parse, "expected #{json.inspect} not to produce a value")
  end

  def assert_partial_value(expected, json)
    parser = new_parser
    parser << json
    refute parser.parse
    2.times do
      assert_equal expected, parser.partial_value
    end
  end

  def assert_resumed_parsing(json, parser = @parser, trailing_bytes: 0)
    expected = JSON.parse(json)

    last_parsed_byte_index = 0
    json.each_byte do |byte|
      parser << byte.chr
      last_parsed_byte_index += 1
      break if parser.parse
    end
    actual = parser.value
    assert_equal expected, actual
    remaining_bytes = (json.bytesize - last_parsed_byte_index)
    assert_equal 0, remaining_bytes, "unconsumed bytes: #{actual.inspect}, remaining: #{json.byteslice(-1, remaining_bytes).inspect}"
    assert_equal json.bytesize - trailing_bytes, parser.parsed_bytes
  end

  def assert_parse_stream(expected, json, parser = @parser)
    actual = []
    parser << json
    while parser.parse
      actual << parser.value
    end
    assert_equal(expected, actual)
  end

  def new_parser(...)
    JSON::ResumableParser.new(...)
  end
end
