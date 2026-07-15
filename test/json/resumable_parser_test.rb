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

  def test_large_numbers_split_across_feeds_are_decoded_correctly
    {
      '12345678901234567890123456789012345678901234567890 ' => 12345678901234567890123456789012345678901234567890,
      '-98765432109876543210987654321 ' => -98765432109876543210987654321,
      '3.14159265358979323846264338327950288 ' => 3.14159265358979323846264338327950288,
      '-1.5e-300 ' => -1.5e-300,
    }.each do |doc, expected|
      parser = new_parser
      value = nil
      doc.each_char do |char|
        parser << char
        value = parser.value if parser.parse
      end
      assert_equal expected, value, doc.inspect
    end
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

  def test_line_comment_spanning_feed_boundary_is_not_terminated_early
    # A `//` line comment is only terminated by a newline. When the newline
    # has not arrived yet, the comment must stay incomplete rather than being
    # treated as consumed -- otherwise its body, delivered in a later chunk,
    # leaks out as parsed values.
    values = []
    parser = new_parser(allow_comments: true)
    parser << '[1] //'
    values << parser.value while parser.parse

    parser << "[2]\n[3]" # [2] belongs to the comment, [3] is a real document
    values << parser.value while parser.parse

    assert_equal [[1], [3]], values
  end

  def test_line_comment_terminated_by_newline_across_feeds
    values = []
    parser = new_parser(allow_comments: true)
    parser << '[1] //co'
    values << parser.value while parser.parse

    parser << "mment\n[2]"
    values << parser.value while parser.parse

    assert_equal [[1], [2]], values
  end

  def test_block_comment_spanning_feed_boundary_is_not_terminated_early
    # A `/* */` block comment whose closing `*/` has not arrived yet must stay
    # incomplete, mirroring the line-comment behaviour above.
    values = []
    parser = new_parser(allow_comments: true)
    parser << '[1] /*'
    values << parser.value while parser.parse

    parser << '[2]*/[3]' # [2] belongs to the comment, [3] is a real document
    values << parser.value while parser.parse

    assert_equal [[1], [3]], values
  end

  def test_trailing_comma_split_across_feed_boundary
    # With allow_trailing_comma the closing bracket may arrive in a later chunk
    # than the comma; consuming the comma must not lose the ability to close.
    parser = new_parser(allow_trailing_comma: true)
    parser << '[1,'
    refute parser.parse
    parser << ']'
    assert parser.parse
    assert_equal [1], parser.value

    parser = new_parser(allow_trailing_comma: true)
    parser << '{"a":1,'
    refute parser.parse
    parser << '}'
    assert parser.parse
    assert_equal({ "a" => 1 }, parser.value)

    # The boundary can also fall after an inner comma, then after the outer one.
    parser = new_parser(allow_trailing_comma: true)
    parser << '[[1,'
    refute parser.parse
    parser << '],]'
    assert parser.parse
    assert_equal [[1]], parser.value
  end

  def test_trailing_comma_byte_by_byte
    parser = new_parser(allow_trailing_comma: true)
    '[1, 2, ]'.each_char { |c| parser << c; parser.parse }
    assert_equal [1, 2], parser.value

    parser = new_parser(allow_trailing_comma: true)
    '{ "a": 1, }'.each_char { |c| parser << c; parser.parse }
    assert_equal({ "a" => 1 }, parser.value)
  end

  def test_comment_after_comma_split_across_feed_boundary
    # A comment right after a ',' straddling a feed boundary must not drop the
    # comma: the value/key it separates must still be parsed on resume.
    # The array case needs allow_trailing_comma: without it the array comma path
    # commits its phase before eating the comment, so only the trailing-comma
    # path exercises the eat-before-commit bug (the object path always did).
    parser = new_parser(allow_comments: true, allow_trailing_comma: true)
    parser << '[1,/*'
    refute parser.parse
    parser << '*/2]'
    assert parser.parse
    assert_equal [1, 2], parser.value

    parser = new_parser(allow_comments: true)
    parser << '{"a":1,/*'
    refute parser.parse
    parser << '*/"b":2}'
    assert parser.parse
    assert_equal({ "a" => 1, "b" => 2 }, parser.value)
  end

  def test_comment_after_container_open_split_across_feed_boundary
    # A comment right after '[' or '{' straddling a feed boundary must not drop
    # the opening token: it is consumed before its frame is pushed, so the
    # suspension must resume from the bracket, not from inside the comment.
    parser = new_parser(allow_comments: true)
    parser << '[/*'
    refute parser.parse
    parser << '*/1]'
    assert parser.parse
    assert_equal [1], parser.value

    parser = new_parser(allow_comments: true)
    parser << '{/*'
    refute parser.parse
    parser << '*/"a":1}'
    assert parser.parse
    assert_equal({ "a" => 1 }, parser.value)

    parser = new_parser(allow_comments: true)
    parser << '[ /*'
    refute parser.parse
    parser << '*/ ]'
    assert parser.parse
    assert_equal [], parser.value

    # The boundary can even split the comment marker itself.
    parser = new_parser(allow_comments: true)
    parser << '[/'
    refute parser.parse
    parser << '**/1]'
    assert parser.parse
    assert_equal [1], parser.value

    # Line comments suspend the same way when their newline hasn't arrived.
    parser = new_parser(allow_comments: true)
    parser << '[//'
    refute parser.parse
    parser << "x\n1]"
    assert parser.parse
    assert_equal [1], parser.value
  end

  def test_rest
    @parser << '[1, 2, 3, "unterminated string'
    refute @parser.parse
    assert_equal '"unterminated string', @parser.rest
  end

  def test_feed_frozen_multibyte_chunks
    @parser << '{"message":"日本'.freeze
    refute @parser.parse
    @parser << '語のつづき"}'.freeze
    assert @parser.parse
    value = @parser.value
    assert_equal({ "message" => "日本語のつづき" }, value)
    assert_equal Encoding::UTF_8, value["message"].encoding
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

  def test_empty_predicate
    # empty? is defined on the state left after parsing everything that
    # could be parsed from the fed bytes, so drain with parse/value first.
    {
      ''               => true,  # nothing fed: vacuously empty
      '{"a":1}'        => true,
      '{"a":1}{"b":2}' => true,
      '{"a":1} '       => true,  # trailing whitespace
      '{"a":1}{"b":2'  => false, # inside a number token
      '{"a":1}{"b":'   => false, # right after a colon (token boundary)
      '{"a":1}{'       => false, # right after an object open
      '{"a":1,'        => false, # right after a comma (token boundary)
      '"abc'           => false, # inside a string token
      '[1,2'           => false, # unclosed array
    }.each do |json, expected|
      parser = new_parser
      parser << json
      parser.value while parser.parse
      assert_equal expected, parser.empty?, "expected #{json.inspect} to be empty? == #{expected}"
    end
  end

  def test_empty_predicate_with_undrained_buffer
    @parser << '{"a":1}{"b":2}'
    assert @parser.parse
    refute_predicate @parser, :empty? # second document still in the buffer
    assert_equal({ "a" => 1 }, @parser.value)
    assert @parser.parse
    assert_equal({ "b" => 2 }, @parser.value)
    assert_predicate @parser, :empty?
  end

  def test_empty_predicate_with_pending_value
    # A fully parsed document awaiting retrieval with #value is not empty.
    @parser << '{"a":1}'
    assert @parser.parse
    refute_predicate @parser, :empty?
    assert_equal({ "a" => 1 }, @parser.value)
    assert_predicate @parser, :empty?
  end

  def test_empty_predicate_across_feeds
    @parser << '{"a' # chunk boundary inside a string literal
    refute @parser.parse
    refute_predicate @parser, :empty?

    @parser << '":1'
    refute @parser.parse
    refute_predicate @parser, :empty?

    @parser << '}'
    assert @parser.parse
    refute_predicate @parser, :empty? # value not retrieved yet
    assert_equal({ "a" => 1 }, @parser.value)
    assert_predicate @parser, :empty?
  end

  def test_partial_value_predicate
    {
      ''               => false,
      '{"a":1}'        => false,
      '{"a":1}{"b":2}' => false,
      '{"a":1} '       => false,
      '{"a":1}{"b":2'  => true,  # inside a number token
      '{"a":1}{"b":'   => true,  # right after a colon (token boundary)
      # The tokenizer rewinds to the token start on EOS, so nothing is
      # registered yet for a lone '{' or an unterminated top-level string:
      # partial_value returns nil and partial_value? agrees. The truncation
      # is still observable through the buffer: eos? is false, rest isn't
      # empty.
      '{"a":1}{'       => false, # right after an object open
      '"abc'           => false, # inside a string token
      '{"a":1,'        => true,  # right after a comma (token boundary)
      '[1,2'           => true,  # unclosed array
    }.each do |json, expected|
      parser = new_parser
      parser << json
      parser.value while parser.parse
      assert_equal expected, parser.partial_value?, "expected #{json.inspect} to be partial_value? == #{expected}"
      assert_equal !parser.partial_value.nil?, parser.partial_value?, "partial_value?/partial_value mismatch for #{json.inspect}"
    end
  end

  def test_partial_value
    assert_nil @parser.partial_value
    assert_partial_value [1, 2, 3], '[1, 2, 3, "unterminated string'
    assert_partial_value({ "a" => 1, "b" => { "c" => nil } }, '{ "a": 1, "b": { "c": "unterminated string')
    assert_partial_value({ "a" => 1, "b" => { "c" => nil } }, '{ "a": 1, "b": { "c"')
    assert_partial_value([1, { "a" => 1, "b" => { "c" => nil } }], '[1, { "a": 1, "b": { "c"')
  end

  def test_partial_value_collapses_nested_incomplete_containers
    # partial_value rebuilds the open containers on a scratch value stack; folding
    # an empty inner container pushes a value, so that stack must hold more than its
    # live size or the push reallocates the scratch buffer.
    assert_partial_value({ "abc" => {} }, '{"abc":{"d')
    assert_partial_value({ "a" => { "b" => { "c" => {} } } }, '{"a":{"b":{"c":{"e')
    assert_partial_value([1, { "a" => {} }], '[1,{"a":{"d')
    assert_partial_value({ "a" => [1, { "b" => [2, { "c" => nil }] }] }, '{"a":[1,{"b":[2,{"c"')
    assert_partial_value([1, [2, [3, { "x" => nil }]]], '[1,[2,[3,{"x":[')
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
