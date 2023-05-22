# frozen_string_literal: true

require "test_helper"

class ParseTest < Test::Unit::TestCase
  test "Ruby 3.2+" do
    assert_operator Gem::Version.new(RUBY_VERSION), :>=, Gem::Version.new("3.2.0"), "ParseTest requires Ruby 3.2+"
  end

  test "empty string" do
    YARP.parse("") => YARP::ParseResult[value: YARP::ProgramNode[statements: YARP::StatementsNode[body: []]]]
  end

  known_failures = %w[
    seattlerb/heredoc_nested.rb
    seattlerb/pct_w_heredoc_interp_nested.rb
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

  Dir[File.expand_path("fixtures/**/*.rb", __dir__)].each do |filepath|
    relative = filepath.delete_prefix("#{File.expand_path("fixtures", __dir__)}/")
    next if known_failures.include?(relative)

    snapshot = File.expand_path(File.join("snapshots", relative), __dir__)
    directory = File.dirname(snapshot)
    FileUtils.mkdir_p(directory) unless File.directory?(directory)

    test(filepath) do
      # First, read the source from the filepath and make sure that it can be
      # correctly parsed by Ripper. If it can't, then we have a fixture that is
      # invalid Ruby.
      source = File.read(filepath)
      refute_nil Ripper.sexp_raw(source)

      # Next, parse the source and print the value.
      result = YARP.parse_file_dup(filepath)
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
