# frozen_string_literal: true

require "yarp_test_helper"

# It is useful to have a diff even if the strings to compare are big
Test::Unit::Assertions::AssertionMessage.max_diff_target_string_size = 5000

class ParseTest < Test::Unit::TestCase
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

  def test_Ruby_3_2_plus
    assert_operator RUBY_VERSION, :>=, "3.2.0", "ParseTest requires Ruby 3.2+"
  end

  def test_empty_string
    YARP.parse("") => YARP::ParseResult[value: YARP::ProgramNode[statements: YARP::StatementsNode[body: []]]]
  end

  known_failures = %w[
    seattlerb/heredoc_nested.txt
  ]

  if RUBY_VERSION < "3.3.0"
    known_failures << "seattlerb/pct_w_heredoc_interp_nested.txt"
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

  def test_parse_dollar0
    parsed_result = YARP.parse("$0", "-e")
    assert_equal 2, parsed_result.value.location.length
  end

  def test_parse_takes_file_path
    filepath = "filepath.rb"
    parsed_result = YARP.parse("def foo; __FILE__; end", filepath)

    assert_equal filepath, find_source_file_node(parsed_result.value).filepath
  end

  root = File.dirname(__dir__)
  # We need valid Ruby files for this test and no "void expression"
  # as that would count as a line in YARP but not with RubyVM::InstructionSequence
  Dir["{lib,test}/**/*.rb", base: root].each do |relative|
    filepath = File.join(root, relative)

    define_method "test_newline_flags_#{relative}" do
      # puts relative

      source = File.read(filepath, binmode: true, external_encoding: Encoding::UTF_8)
      verbose, $VERBOSE = $VERBOSE, nil
      begin
        insns = RubyVM::InstructionSequence.compile(source)
      ensure
        $VERBOSE = verbose
      end

      queue = [insns]
      cruby_lines = []
      while iseq = queue.shift
        iseq.trace_points.each do |line, event|
          cruby_lines << line if event == :line
        end
        iseq.each_child do |insn|
          queue << insn unless insn.label.start_with?('ensure in ')
        end
      end
      cruby_lines.sort!

      result = YARP.parse(source, relative)
      assert_empty result.errors

      result.mark_newlines
      ast = result.value
      yarp_lines = []
      visitor = Class.new(YARP::Visitor) do
        define_method(:visit) do |node|
          if node and node.newline?
            yarp_lines << result.source.line(node.location.start_offset)
          end
          super(node)
        end
      end
      ast.accept(visitor.new)

      if relative == 'lib/yarp/serialize.rb'
        # while (b = io.getbyte) >= 128 has 2 newline flags
        cruby_lines.delete_at yarp_lines.index(62)
      elsif relative == 'lib/yarp/lex_compat.rb'
        # extra flag for: dedent_next =\n  ((token.event: due to bytecode order
        yarp_lines.delete(514)
        # different line for: token =\n  case event: due to bytecode order
        yarp_lines.delete(571)
        cruby_lines.delete(572)
        # extra flag for: lex_state =\n  if RIPPER: due to bytecode order
        yarp_lines.delete(604)
        # extra flag for: (token[2].start_with?("\#$") || token[2].start_with?("\#@"))
        # unclear when ParenthesesNode should allow a second flag on the same line or not
        yarp_lines.delete(731)
      end

      assert_equal cruby_lines, yarp_lines
    end
  end

  base = File.join(__dir__, "fixtures")
  Dir["**/*.txt", base: base].each do |relative|
    next if known_failures.include?(relative)

    filepath = File.join(base, relative)
    snapshot = File.expand_path(File.join("snapshots", relative), __dir__)
    directory = File.dirname(snapshot)
    FileUtils.mkdir_p(directory) unless File.directory?(directory)

    define_method "test_filepath_#{relative}" do
      # First, read the source from the filepath. Use binmode to avoid converting CRLF on Windows,
      # and explicitly set the external encoding to UTF-8 to override the binmode default.
      source = File.read(filepath, binmode: true, external_encoding: Encoding::UTF_8)

      # Make sure that it can be correctly parsed by Ripper. If it can't, then we have a fixture
      # that is invalid Ruby.
      refute_nil Ripper.sexp_raw(source)

      # Next, assert that there were no errors during parsing.
      result = YARP.parse(source, relative)
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

      # Next, assert that the value can be serialized and deserialized without
      # changing the shape of the tree.
      assert_equal_nodes(result.value, YARP.load(source, YARP.dump(source, relative)))

      # Next, assert that the newlines are in the expected places.
      expected_newlines = [0]
      source.b.scan("\n") { expected_newlines << $~.offset(0)[0] + 1 }
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

  private

  def ignore_warnings
    previous_verbosity = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = previous_verbosity
  end
end
