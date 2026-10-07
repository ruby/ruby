# frozen_string_literal: true

require_relative "../test_helper"

module Ruby::Prism
  class ParseTest < TestCase
    def test_parse_result
      result = Ruby::Prism.parse("")
      assert_kind_of ParseResult, result

      result = Ruby::Prism.parse_file(__FILE__)
      assert_kind_of ParseResult, result
    end

    def test_parse_empty_string
      result = Ruby::Prism.parse("")
      assert_equal [], result.value.statements.body
    end

    def test_parse_takes_file_path
      filepath = "filepath.rb"
      result = Ruby::Prism.parse("def foo; __FILE__; end", filepath: filepath)

      assert_equal filepath, find_source_file_node(result.value).filepath
    end

    def test_parse_takes_line
      line = 4
      result = Ruby::Prism.parse("def foo\n __FILE__\nend", line: line)

      assert_equal line, result.value.location.start_line
      assert_equal line + 1, find_source_file_node(result.value).location.start_line

      result = Ruby::Prism.parse_lex("def foo\n __FILE__\nend", line: line)
      assert_equal line, result.value.first.location.start_line
    end

    def test_parse_takes_negative_lines
      line = -2
      result = Ruby::Prism.parse("def foo\n __FILE__\nend", line: line)

      assert_equal line, result.value.location.start_line
      assert_equal line + 1, find_source_file_node(result.value).location.start_line

      result = Ruby::Prism.parse_lex("def foo\n __FILE__\nend", line: line)
      assert_equal line, result.value.first.location.start_line
    end

    def test_parse_file
      node = Ruby::Prism.parse_file(__FILE__).value
      assert_kind_of ProgramNode, node

      error = assert_raise Errno::ENOENT do
        Ruby::Prism.parse_file("idontexist.rb")
      end

      assert_equal "No such file or directory - idontexist.rb", error.message

      assert_raise TypeError do
        Ruby::Prism.parse_file(nil)
      end
    end

    def test_parse_tempfile
      Tempfile.create(["test_parse_tempfile", ".rb"]) do |t|
        t.puts ["begin\n", " end\n"]
        t.flush
        Ruby::Prism.parse_file(t.path)
      end
    end

    def test_parse_pathname
      pathname = Pathname.new(__FILE__)
      node = Ruby::Prism.parse_file(pathname).value
      assert_kind_of ProgramNode, node
    end

    if RUBY_ENGINE != "truffleruby"
      def test_parse_nonascii
        Dir.mktmpdir do |dir|
          path = File.join(dir, "\u{3042 3044 3046 3048 304a}.rb".encode(Encoding::Windows_31J))
          File.write(path, "ok")
          Ruby::Prism.parse_file(path)
        end
      end
    end

    def test_parse_directory
      error = nil

      begin
        Ruby::Prism.parse_file(__dir__)
      rescue SystemCallError => error
      end

      assert_kind_of Errno::EISDIR, error
    end

    def test_partial_script
      assert Ruby::Prism.parse_failure?("break")
      assert Ruby::Prism.parse_success?("break", partial_script: true)

      assert Ruby::Prism.parse_failure?("next")
      assert Ruby::Prism.parse_success?("next", partial_script: true)

      assert Ruby::Prism.parse_failure?("redo")
      assert Ruby::Prism.parse_success?("redo", partial_script: true)

      assert Ruby::Prism.parse_failure?("yield")
      assert Ruby::Prism.parse_success?("yield", partial_script: true)
    end

    def test_version
      assert Ruby::Prism.parse_success?("1 + 1", version: "3.3")
      assert Ruby::Prism.parse_success?("1 + 1", version: "3.3.0")
      assert Ruby::Prism.parse_success?("1 + 1", version: "3.3.1")
      assert Ruby::Prism.parse_success?("1 + 1", version: "3.3.9")
      assert Ruby::Prism.parse_success?("1 + 1", version: "3.3.10")

      assert Ruby::Prism.parse_success?("1 + 1", version: "3.4")
      assert Ruby::Prism.parse_success?("1 + 1", version: "3.4.0")
      assert Ruby::Prism.parse_success?("1 + 1", version: "3.4.9")
      assert Ruby::Prism.parse_success?("1 + 1", version: "3.4.10")

      assert Ruby::Prism.parse_success?("1 + 1", version: "3.5")
      assert Ruby::Prism.parse_success?("1 + 1", version: "3.5.0")

      assert Ruby::Prism.parse_success?("1 + 1", version: "4.0")
      assert Ruby::Prism.parse_success?("1 + 1", version: "4.0.0")

      assert Ruby::Prism.parse_success?("1 + 1", version: "4.1")
      assert Ruby::Prism.parse_success?("1 + 1", version: "4.1.0")

      assert Ruby::Prism.parse_success?("1 + 1", version: "latest")

      # Test edge case
      error = assert_raise(ArgumentError) { Ruby::Prism.parse("1 + 1", version: "latest2") }
      assert_equal "invalid version: latest2", error.message

      assert_raise ArgumentError do
        Ruby::Prism.parse("1 + 1", version: "3.3.a")
      end

      # Not supported version (too old)
      assert_raise ArgumentError do
        Ruby::Prism.parse("1 + 1", version: "3.2.0")
      end

      # Not supported version (too new)
      assert_raise ArgumentError do
        Ruby::Prism.parse("1 + 1", version: "3.6.0")
      end
    end

    def test_version_current
      if RUBY_VERSION >= "3.3"
        assert Ruby::Prism.parse_success?("1 + 1", version: "current")
      else
        assert_raise(CurrentVersionError) { Ruby::Prism.parse_success?("1 + 1", version: "current") }
      end
    end

    def test_nearest
      assert Ruby::Prism.parse_success?("1 + 1", version: "nearest")
    end

    def test_scopes
      assert_kind_of Ruby::Prism::CallNode, Ruby::Prism.parse_statement("foo")
      assert_kind_of Ruby::Prism::LocalVariableReadNode, Ruby::Prism.parse_statement("foo", scopes: [[:foo]])
      assert_kind_of Ruby::Prism::LocalVariableReadNode, Ruby::Prism.parse_statement("foo", scopes: [Ruby::Prism.scope(locals: [:foo])])

      assert Ruby::Prism.parse_failure?("foo(*)")
      assert Ruby::Prism.parse_success?("foo(*)", scopes: [Ruby::Prism.scope(forwarding: [:*])])

      assert Ruby::Prism.parse_failure?("foo(**)")
      assert Ruby::Prism.parse_success?("foo(**)", scopes: [Ruby::Prism.scope(forwarding: [:**])])

      assert Ruby::Prism.parse_failure?("foo(&)")
      assert Ruby::Prism.parse_success?("foo(&)", scopes: [Ruby::Prism.scope(forwarding: [:&])])

      assert Ruby::Prism.parse_failure?("foo(...)")
      assert Ruby::Prism.parse_success?("foo(...)", scopes: [Ruby::Prism.scope(forwarding: [:"..."])])
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
