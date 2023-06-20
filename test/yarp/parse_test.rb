# frozen_string_literal: true

require "yarp_test_helper"

class ParseTest < Test::Unit::TestCase
  def test_Ruby_3_2_plus
    assert_operator RUBY_VERSION, :>=, "3.2.0", "ParseTest requires Ruby 3.2+"
  end

  def test_empty_string
    YARP.parse("") => YARP::ParseResult[value: YARP::ProgramNode[statements: YARP::StatementsNode[body: []]]]
  end

  known_failures = %w[
    seattlerb/heredoc_nested.txt
    seattlerb/pct_w_heredoc_interp_nested.txt
  ]

  # Because the filepath in SourceFileNodes is different from one maching to the
  # next, PP.pp(sexp, +"", 79) can have different results: both the path itself
  # and the line breaks based on the length of the path.
  def normalize_printed(printed)
    printed
      .gsub(
        /SourceFileNode \s*
          \(\s* (\d+\.\.\.\d+) \s*\) \s*
          \(\s* ("[^"]*")      \s*\)
        /mx,
        'SourceFileNode(\1)(\2)')
      .gsub(__dir__, "")
  end

  def find_source_file_node(node)
    if node.is_a?(YARP::SourceFileNode)
      node
    else
      node && node.child_nodes.each do |child_node|
        source_file_node = find_source_file_node(child_node)
        return source_file_node if source_file_node
      end
    end
  end

  def test_parse_takes_file_path
    filepath = "filepath.rb"
    parsed_result = YARP.parse("def foo; __FILE__; end", filepath)

    assert_equal filepath, find_source_file_node(parsed_result.value).filepath
  end

  Dir[File.expand_path("fixtures/**/*.txt", __dir__)].each do |filepath|
    relative = filepath.delete_prefix("#{File.expand_path("fixtures", __dir__)}/")
    next if known_failures.include?(relative)

    snapshot = File.expand_path(File.join("snapshots", relative), __dir__)
    directory = File.dirname(snapshot)
    FileUtils.mkdir_p(directory) unless File.directory?(directory)

    define_method "test_filepath_#{filepath}" do
      # First, read the source from the filepath. Use binmode to avoid converting CRLF on Windows,
      # and explicitly set the external encoding to UTF-8 to override the binmode default.
      source = File.read(filepath, binmode: true, external_encoding: Encoding::UTF_8)

      # Make sure that it can be correctly parsed by Ripper. If it can't, then we have a fixture
      # that is invalid Ruby.
      refute_nil Ripper.sexp_raw(source)

      # Next, parse the source and print the value.
      result = YARP.parse_file(filepath)
      value = result.value
      printed = normalize_printed(PP.pp(value, +"", 79))

      # Next, assert that there were no errors during parsing.
      assert_empty result.errors, value

      if File.exist?(snapshot)
        expected = File.read(snapshot)
        normalized = normalize_printed(expected)
        if expected != normalized
          File.write(snapshot, normalized)
          warn("Updated snapshot at #{snapshot}.")
        end
        # If the snapshot file exists, then assert that the printed value
        # matches the snapshot.
        assert_equal(normalized, printed)
      else
        # If the snapshot file does not yet exist, then write it out now.
        File.write(snapshot, printed)
        warn("Created snapshot at #{snapshot}.")
      end

      # Next, assert that the value can be serialized and deserialized without
      # changing the shape of the tree.
      assert_equal_nodes(value, YARP.load(source, YARP.dump(source, filepath)))

      # Next, assert that the newlines are in the expected places.
      expected_newlines = [0]
      source.b.scan("\n") { expected_newlines << $~.offset(0)[0] }
      assert_equal expected_newlines, YARP.newlines(source)

      # Finally, assert that we can lex the source and get the same tokens as
      # Ripper.
      YARP.lex_compat(source) => { errors: [], value: tokens }

      begin
        YARP.lex_ripper(source).zip(tokens).each do |(ripper, yarp)|
          assert_equal ripper, yarp
        end
      rescue SyntaxError
        raise ArgumentError, "Test file has invalid syntax #{filepath}"
      end
    end
  end
end
