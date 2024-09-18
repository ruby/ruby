# frozen_string_literal: true

require_relative "../test_helper"

module Prism
  class ParseTest < TestCase
    def test_parse_result
      result = Prism.parse("")
      assert_kind_of ParseResult, result

      result = Prism.parse_file(__FILE__)
      assert_kind_of ParseResult, result
    end

    def test_parse_empty_string
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

    def test_parse_tempfile
      Tempfile.create(["test_parse_tempfile", ".rb"]) do |t|
        t.puts ["begin\n", " end\n"]
        t.flush
        Prism.parse_file(t.path)
      end
    end

    if RUBY_ENGINE != "truffleruby"
      def test_parse_nonascii
        Dir.mktmpdir do |dir|
          path = File.join(dir, "\u{3042 3044 3046 3048 304a}.rb".encode(Encoding::Windows_31J))
          File.write(path, "ok")
          Prism.parse_file(path)
        end
      end
    end

    def test_parse_directory
      error = nil

      begin
        Prism.parse_file(__dir__)
      rescue SystemCallError => error
      end

      assert_kind_of Errno::EISDIR, error
    end

    private

    def find_source_file_node(program)
      queue = [program]
      while (node = queue.shift)
        return node if node.is_a?(SourceFileNode)
        queue.concat(node.compact_child_nodes)
      end
    end
  end
end
