# frozen_string_literal: true

require_relative "../test_helper"

module Ruby::Prism
  class AttachCommentsTest < TestCase
    Fixture.each do |fixture|
      define_method(fixture.test_name) { assert_attachments(fixture.read) }
    end

    def test_trailing_ties_go_to_the_higher_node
      assert_attached({ "# c" => [:alias_method_node, "alias :foo :bar"] }, "alias :foo :bar # c")
    end

    def test_trailing_goes_to_the_node_ending_on_the_line
      assert_attached({ "# c" => [:symbol_node, ":foo"] }, "alias :foo # c\n:bar")
    end

    def test_trailing_in_body
      assert_attached({ "# c" => [:call_node, "a"] }, "def foo\na # c\nb\nend")
    end

    def test_trailing_after_heredoc_opener
      assert_attached({ "# c" => [:call_node, "foo(<<~A)"] }, "foo(<<~A) # c\n  x\nA\n")
    end

    def test_trailing_after_last_statement
      assert_attached({ "# c" => [:call_node, "b"] }, "a\nb # c")
    end

    def test_own_line_goes_to_the_innermost_enclosing_node
      assert_attached({ "# c" => [:statements_node, "a\n# c\nb"] }, "def foo\na\n# c\nb\nend")
    end

    def test_own_line_in_arguments
      assert_attached({ "# c" => [:call_node, "foo(# c\n x)"] }, "foo(# c\n x)")
    end

    def test_own_line_before_class_body
      assert_attached({ "# doc" => [:statements_node, "def b; end"] }, "class A\n  # doc\n  def b; end\nend")
    end

    def test_own_line_block_before_body
      assert_attached({ "# a" => [:statements_node, "def b; end"], "# b" => [:statements_node, "def b; end"] }, "class A\n  # a\n\n  # b\n  def b; end\nend")
    end

    def test_own_line_before_method_body
      assert_attached({ "# c" => [:statements_node, "body"] }, "def foo(a)\n  # c\n  body\nend")
    end

    def test_own_line_before_block_body
      assert_attached({ "# c" => [:statements_node, "bar"] }, "foo do |x|\n  # c\n  bar\nend")
    end

    def test_own_line_separated_from_body
      assert_attached({ "# c" => [:def_node, "def foo(a\n  # c\n)\n  body\nend"] }, "def foo(a\n  # c\n)\n  body\nend")
    end

    def test_own_line_after_class_body
      assert_attached({ "# note" => [:statements_node, "def x; end"] }, "class A\n  def x; end\n  # note\nend")
    end

    def test_embdoc_before_and_after_class_body
      source = "class A\n=begin\nbefore\n=end\n  def b; end\n=begin\nafter\n=end\nend"
      assert_attached({ "=begin\nbefore\n=end\n" => [:statements_node, "def b; end"], "=begin\nafter\n=end\n" => [:statements_node, "def b; end"] }, source)
    end

    def test_own_line_after_method_body
      assert_attached({ "# c" => [:statements_node, "a"] }, "def foo\n  a\n  # c\nend")
    end

    def test_own_line_around_class_body
      assert_attached({ "# doc" => [:statements_node, "def b; end"], "# tail" => [:statements_node, "def b; end"] }, "class A\n  # doc\n  def b; end\n  # tail\nend")
    end

    def test_own_line_after_branch_bodies
      assert_attached({ "# c" => [:statements_node, "b"], "# e" => [:statements_node, "d"] }, "if a\n  b\n  # c\nelse\n  d\n  # e\nend")
    end

    def test_own_line_after_rescue_body
      assert_attached({ "# c" => [:statements_node, "b"] }, "def foo\n  a\nrescue\n  b\n  # c\nend")
    end

    def test_own_line_after_each_rescue_body
      assert_attached({ "# c1" => [:statements_node, "x"], "# c2" => [:statements_node, "y"] }, "begin\n  a\nrescue A\n  x\n  # c1\nrescue B\n  y\n  # c2\nend")
    end

    def test_own_line_after_rescue_body_before_ensure
      assert_attached({ "# c" => [:statements_node, "b"] }, "def foo\n  a\nrescue => e\n  b\n  # c\nensure\n  z\nend")
    end

    def test_own_line_in_empty_rescue_body
      assert_attached({ "# c" => [:begin_node, "def foo\n  a\nrescue\n  # c\nend"] }, "def foo\n  a\nrescue\n  # c\nend")
    end

    def test_own_line_after_block_body
      assert_attached({ "# c" => [:statements_node, "bar"] }, "foo do\n  bar\n  # c\nend")
    end

    def test_own_line_in_empty_class_body
      assert_attached({ "# c" => [:class_node, "class A\n  # c\nend"] }, "class A\n  # c\nend")
    end

    def test_own_line_at_top_level
      assert_attached({ "# doc" => [:statements_node, "def foo; end"] }, "# doc\ndef foo; end")
    end

    def test_only_comments
      assert_attached({ "# only" => [:statements_node, ""] }, "# only")
    end

    def test_embdoc
      assert_attached({ "=begin\nembdoc\n=end\n" => [:statements_node, "foo"] }, "=begin\nembdoc\n=end\nfoo")
    end

    def test_comments_around_a_child
      source = "foo(# a\n x, # m\n y) # b"
      call = "foo(# a\n x, # m\n y)"

      assert_attached({ "# a" => [:call_node, call], "# m" => [:call_node, "x"], "# b" => [:call_node, call] }, source)
    end

    def test_heredoc_body_inside_later_sibling
      source = "foo(<<~A, [\n  \#{ # c\n  x }\nA\n  1])\n"
      assert_attached({ "# c" => [:statements_node, "x"] }, source)
    end

    def test_heredoc_part_ending_in_newline
      source = "<<~A\n  text\n  \#{ # c\n  x }\nA\n"
      assert_attached({ "# c" => [:statements_node, "x"] }, source)
    end

    def test_heredoc_comments_are_sorted
      source = "foo(<<~A) # after\n  \#{x # body\n  }\nA\n"

      assert_equal ["# after", "# body"], Ruby::Prism.parse(source, attach_comments: true).comments.map(&:slice)
      assert_equal ["# body", "# after"], Ruby::Prism.parse(source).comments.map(&:slice)
    end

    def test_nested_heredoc_comments
      source = "foo(<<~A, <<~B) # after\n  \#{x # body a\n  }\nA\n  \#{y # body b\n  }\nB\n"

      assert_attached(
        {
          "# after" => [:call_node, "foo(<<~A, <<~B)"],
          "# body a" => [:call_node, "x"],
          "# body b" => [:call_node, "y"]
        },
        source
      )
    end

    def test_comments_are_shared_with_the_result
      result = Ruby::Prism.parse("foo # c", attach_comments: true)
      assert_same result.comments.first, result.value.statements.body.first.comments.first
    end

    def test_without_attach_comments
      result = Ruby::Prism.parse("foo # c")
      each_node(result.value) { |node| assert_empty node.comments }
    end

    def test_freeze
      result = Ruby::Prism.parse("foo # c", attach_comments: true, freeze: true)
      comments = result.value.statements.body.first.comments

      assert_equal ["# c"], comments.map(&:slice)
      assert_predicate result.source.comment_attachments, :frozen?
      assert_predicate result.source.comment_ranges, :frozen?
      assert Ractor.shareable?(result) if defined?(Ractor.shareable?)
    end

    def test_parse_lex
      node, = Ruby::Prism.parse_lex("foo # c", attach_comments: true).value
      assert_equal ["# c"], node.statements.body.first.comments.map(&:slice)
    end

    def test_parse_stream
      result = Ruby::Prism.parse_stream(StringIO.new("foo # c"), attach_comments: true)
      assert_equal ["# c"], result.value.statements.body.first.comments.map(&:slice)
    end

    private

    # Assert that each comment in the source is attached to the node with the
    # given type and slice.
    def assert_attached(expected, source)
      actual = {}

      each_node(Ruby::Prism.parse(source, attach_comments: true).value) do |node|
        node.comments.each { |comment| actual[comment.slice] = [node.type, node.slice] }
      end

      assert_equal expected, actual
    end

    # Assert that every comment is attached to exactly one node, that each
    # node's comments are sorted, and that each node only owns comments on the
    # lines it covers. The exceptions are statements nodes, which own the
    # comments that come before or after them with only whitespace and comments
    # in between, and the top-level statements, which own the comments that no
    # other node covers.
    def assert_attachments(source)
      result = Ruby::Prism.parse(source, attach_comments: true)
      offsets = result.comments.map { |comment| comment.location.start_offset }
      assert_equal offsets.sort, offsets

      top = result.value.statements
      attached = []

      each_node(result.value) do |node|
        comments = node.comments
        assert_equal comments.sort_by { |comment| comment.location.start_offset }, comments
        attached.concat(comments)

        next if node.equal?(top)

        location = node.location
        end_line = location.length == 0 ? location.start_line : result.source.line(location.end_offset - 1)

        comments.each do |comment|
          if node.is_a?(StatementsNode) && (comment.location.end_offset <= location.start_offset || comment.location.start_offset >= location.end_offset)
            range = comment.location.end_offset <= location.start_offset ? (comment.location.end_offset...location.start_offset) : (location.end_offset...comment.location.start_offset)
            gap = result.source.source.byteslice(range)
            result.comments.each { |other| gap = gap.sub(other.slice, "") if gap.include?(other.slice) }
            assert_match(/\A\s*\z/, gap)
          else
            assert_operator comment.location.start_line, :>=, location.start_line
            assert_operator comment.location.start_line, :<=, end_line
          end
        end
      end

      assert_equal result.comments.map(&:object_id).sort, attached.map(&:object_id).sort

      if !ENV["PRISM_BUILD_MINIMAL"]
        loaded = Ruby::Prism.load(source, Ruby::Prism.dump(source, attach_comments: true))
        assert_equal attachments(result.value), attachments(loaded.value)
      end
    end

    # The start offsets of the comments attached to each node, keyed by node id.
    def attachments(root)
      attachments = {}

      each_node(root) do |node|
        attachments[node.node_id] = node.comments.map { |comment| comment.location.start_offset } if node.comments.any?
      end

      attachments
    end

    def each_node(root)
      queue = [root]

      while (node = queue.shift)
        yield node
        queue.concat(node.compact_child_nodes)
      end
    end
  end
end
