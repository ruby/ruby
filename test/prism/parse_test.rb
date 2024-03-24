# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class ParseTest < TestCase
    # A subclass of Ripper that extracts out magic comments.
    class MagicCommentRipper < Ripper
      attr_reader :magic_comments

      def initialize(*)
        super
        @magic_comments = []
      end

      def on_magic_comment(key, value)
        @magic_comments << [key, value]
        super
      end
    end

    # When we pretty-print the trees to compare against the snapshots, we want to
    # be certain that we print with the same external encoding. This is because
    # methods like Symbol#inspect take into account external encoding and it could
    # change how the snapshot is generated. On machines with certain settings
    # (like LANG=C or -Eascii-8bit) this could have been changed. So here we're
    # going to force it to be UTF-8 to keep the snapshots consistent.
    def setup
      @previous_default_external = Encoding.default_external
      ignore_warnings { Encoding.default_external = Encoding::UTF_8 }
    end

    def teardown
      ignore_warnings { Encoding.default_external = @previous_default_external }
    end

    def test_empty_string
      result = Prism.parse("")
      assert_equal [], result.value.statements.body
    end

    def test_parse_takes_file_path
      filepath = "filepath.rb"
      result = Prism.parse("def foo; __FILE__; end", filepath: filepath)

      assert_equal filepath, find_source_file_node(result.value).filepath
    end

    def test_parse_takes_line
      line = 4
      result = Prism.parse("def foo\n __FILE__\nend", line: line)

      assert_equal line, result.value.location.start_line
      assert_equal line + 1, find_source_file_node(result.value).location.start_line

      result = Prism.parse_lex("def foo\n __FILE__\nend", line: line)
      assert_equal line, result.value.first.location.start_line
    end

    def test_parse_takes_negative_lines
      line = -2
      result = Prism.parse("def foo\n __FILE__\nend", line: line)

      assert_equal line, result.value.location.start_line
      assert_equal line + 1, find_source_file_node(result.value).location.start_line

      result = Prism.parse_lex("def foo\n __FILE__\nend", line: line)
      assert_equal line, result.value.first.location.start_line
    end

    def test_parse_lex
      node, tokens = Prism.parse_lex("def foo; end").value

      assert_kind_of ProgramNode, node
      assert_equal 5, tokens.length
    end

    if !ENV["PRISM_BUILD_MINIMAL"]
      def test_dump_file
        assert_nothing_raised do
          Prism.dump_file(__FILE__)
        end

        error = assert_raise Errno::ENOENT do
          Prism.dump_file("idontexist.rb")
        end

        assert_equal "No such file or directory - idontexist.rb", error.message

        assert_raise TypeError do
          Prism.dump_file(nil)
        end
      end
    end

    def test_lex_file
      assert_nothing_raised do
        Prism.lex_file(__FILE__)
      end

      error = assert_raise Errno::ENOENT do
        Prism.lex_file("idontexist.rb")
      end

      assert_equal "No such file or directory - idontexist.rb", error.message

      assert_raise TypeError do
        Prism.lex_file(nil)
      end
    end

    def test_parse_lex_file
      node, tokens = Prism.parse_lex_file(__FILE__).value

      assert_kind_of ProgramNode, node
      refute_empty tokens

      error = assert_raise Errno::ENOENT do
        Prism.parse_lex_file("idontexist.rb")
      end

      assert_equal "No such file or directory - idontexist.rb", error.message

      assert_raise TypeError do
        Prism.parse_lex_file(nil)
      end
    end

    def test_parse_file
      node = Prism.parse_file(__FILE__).value
      assert_kind_of ProgramNode, node

      error = assert_raise Errno::ENOENT do
        Prism.parse_file("idontexist.rb")
      end

      assert_equal "No such file or directory - idontexist.rb", error.message

      assert_raise TypeError do
        Prism.parse_file(nil)
      end
    end

    def test_parse_file_success
      assert_predicate Prism.parse_file_comments(__FILE__), :any?

      error = assert_raise Errno::ENOENT do
        Prism.parse_file_comments("idontexist.rb")
      end

      assert_equal "No such file or directory - idontexist.rb", error.message

      assert_raise TypeError do
        Prism.parse_file_comments(nil)
      end
    end

    def test_parse_file_comments
      assert_predicate Prism.parse_file_comments(__FILE__), :any?

      error = assert_raise Errno::ENOENT do
        Prism.parse_file_comments("idontexist.rb")
      end

      assert_equal "No such file or directory - idontexist.rb", error.message

      assert_raise TypeError do
        Prism.parse_file_comments(nil)
      end
    end

    # To accurately compare against Ripper, we need to make sure that we're
    # running on CRuby 3.2+.
    ripper_enabled = RUBY_ENGINE == "ruby" && RUBY_VERSION >= "3.2.0"

    # The FOCUS environment variable allows you to specify one particular fixture
    # to test, instead of all of them.
    base = File.join(__dir__, "fixtures")
    relatives = ENV["FOCUS"] ? [ENV["FOCUS"]] : Dir["**/*.txt", base: base]

    relatives.each do |relative|
      # These fail on TruffleRuby due to a difference in Symbol#inspect: :测试 vs :"测试"
      next if RUBY_ENGINE == "truffleruby" and %w[emoji_method_calls.txt seattlerb/bug202.txt seattlerb/magic_encoding_comment.txt].include?(relative)

      filepath = File.join(base, relative)
      snapshot = File.expand_path(File.join("snapshots", relative), __dir__)

      directory = File.dirname(snapshot)
      FileUtils.mkdir_p(directory) unless File.directory?(directory)

      ripper_should_parse = ripper_should_match = ripper_enabled

      # This file has changed behavior in Ripper in Ruby 3.3, so we skip it if
      # we're on an earlier version.
      ripper_should_match = false if relative == "seattlerb/pct_w_heredoc_interp_nested.txt" && RUBY_VERSION < "3.3.0"

      # It seems like there are some oddities with nested heredocs and ripper.
      # Waiting for feedback on https://bugs.ruby-lang.org/issues/19838.
      ripper_should_match = false if relative == "seattlerb/heredoc_nested.txt"

      # Ripper seems to have a bug that the regex portions before and after the heredoc are combined
      # into a single token. See https://bugs.ruby-lang.org/issues/19838.
      #
      # Additionally, Ripper cannot parse the %w[] fixture in this file, so set ripper_should_parse to false.
      ripper_should_parse = false if relative == "spanning_heredoc.txt"

      # Ruby < 3.3.0 cannot parse heredocs where there are leading whitespace characters in the heredoc start.
      # Example: <<~'   EOF' or <<-'  EOF'
      # https://bugs.ruby-lang.org/issues/19539
      ripper_should_parse = false if relative == "heredocs_leading_whitespace.txt" && RUBY_VERSION < "3.3.0"

      define_method "test_filepath_#{relative}" do
        # First, read the source from the filepath. Use binmode to avoid converting CRLF on Windows,
        # and explicitly set the external encoding to UTF-8 to override the binmode default.
        source = File.read(filepath, binmode: true, external_encoding: Encoding::UTF_8)

        if ripper_should_parse
          src = source

          case relative
          when /break|next|redo|if|unless|rescue|control|keywords|retry/
            # Uncaught syntax errors: Invalid break, Invalid next
            src = "->do\nrescue\n#{src}\nend"
            ripper_should_match = false
          end
          case src
          when /^ *yield/
            # Uncaught syntax errors: Invalid yield
            src = "def __invalid_yield__\n#{src}\nend"
            ripper_should_match = false
          end

          # Make sure that it can be correctly parsed by Ripper. If it can't, then we have a fixture
          # that is invalid Ruby.
          refute_nil(Ripper.sexp_raw(src), "Ripper failed to parse")
        end

        # Next, assert that there were no errors during parsing.
        result = Prism.parse(source, filepath: relative)
        assert_empty result.errors

        # Next, pretty print the source.
        printed = PP.pp(result.value, +"", 79)

        if File.exist?(snapshot)
          saved = File.read(snapshot)

          # If the snapshot file exists, but the printed value does not match the
          # snapshot, then update the snapshot file.
          if printed != saved
            File.write(snapshot, printed)
            warn("Updated snapshot at #{snapshot}.")
          end

          # If the snapshot file exists, then assert that the printed value
          # matches the snapshot.
          assert_equal(saved, printed)
        else
          # If the snapshot file does not yet exist, then write it out now.
          File.write(snapshot, printed)
          warn("Created snapshot at #{snapshot}.")
        end

        if !ENV["PRISM_BUILD_MINIMAL"]
          # Next, assert that the value can be serialized and deserialized
          # without changing the shape of the tree.
          assert_equal_nodes(result.value, Prism.load(source, Prism.dump(source, filepath: relative)).value)
        end

        # Next, check that the location ranges of each node in the tree are a
        # superset of their respective child nodes.
        assert_non_overlapping_locations(result.value)

        # Next, assert that the newlines are in the expected places.
        expected_newlines = [0]
        source.b.scan("\n") { expected_newlines << $~.offset(0)[0] + 1 }
        assert_equal expected_newlines, Debug.newlines(source)

        if ripper_should_parse && ripper_should_match
          # Finally, assert that we can lex the source and get the same tokens as
          # Ripper.
          lex_result = Prism.lex_compat(source)
          assert_equal [], lex_result.errors
          tokens = lex_result.value

          begin
            Prism.lex_ripper(source).zip(tokens).each do |(ripper, prism)|
              assert_equal ripper, prism
            end
          rescue SyntaxError
            raise ArgumentError, "Test file has invalid syntax #{filepath}"
          end

          # Next, check that we get the correct number of magic comments when
          # lexing with ripper.
          expected = MagicCommentRipper.new(source).tap(&:parse).magic_comments
          actual = result.magic_comments

          assert_equal expected.length, actual.length
          expected.zip(actual).each do |(expected_key, expected_value), magic_comment|
            assert_equal expected_key, magic_comment.key
            assert_equal expected_value, magic_comment.value
          end
        end
      end
    end

    Dir["*.txt", base: base].each do |relative|
      next if relative == "newline_terminated.txt" || relative == "spanning_heredoc_newlines.txt"

      # We test every snippet (separated by \n\n) in isolation
      # to ensure the parser does not try to read bytes further than the end of each snippet
      define_method "test_individual_snippets_#{relative}" do
        filepath = File.join(base, relative)

        # First, read the source from the filepath. Use binmode to avoid converting CRLF on Windows,
        # and explicitly set the external encoding to UTF-8 to override the binmode default.
        file_contents = File.read(filepath, binmode: true, external_encoding: Encoding::UTF_8)

        file_contents.split(/(?<=\S)\n\n(?=\S)/).each do |snippet|
          snippet = snippet.rstrip
          result = Prism.parse(snippet, filepath: relative)
          assert_empty result.errors

          if !ENV["PRISM_BUILD_MINIMAL"]
            assert_equal_nodes(result.value, Prism.load(snippet, Prism.dump(snippet, filepath: relative)).value)
          end
        end
      end
    end

    private

    # Check that the location ranges of each node in the tree are a superset of
    # their respective child nodes.
    def assert_non_overlapping_locations(node)
      queue = [node]

      while (current = queue.shift)
        # We only want to compare parent/child location overlap in the case that
        # we are not looking at a heredoc. That's because heredoc locations are
        # special in that they only use the declaration of the heredoc.
        compare = !(current.is_a?(StringNode) ||
                    current.is_a?(XStringNode) ||
                    current.is_a?(InterpolatedStringNode) ||
                    current.is_a?(InterpolatedXStringNode)) ||
        !current.opening&.start_with?("<<")

        current.child_nodes.each do |child|
          # child_nodes can return nil values, so we need to skip those.
          next unless child

          # Now that we know we have a child node, add that to the queue.
          queue << child

          if compare
            assert_operator current.location.start_offset, :<=, child.location.start_offset
            assert_operator current.location.end_offset, :>=, child.location.end_offset
          end
        end
      end
    end

    def find_source_file_node(program)
      queue = [program]
      while (node = queue.shift)
        return node if node.is_a?(SourceFileNode)
        queue.concat(node.compact_child_nodes)
      end
    end

    def ignore_warnings
      previous_verbosity = $VERBOSE
      $VERBOSE = nil
      yield
    ensure
      $VERBOSE = previous_verbosity
    end
  end
end
