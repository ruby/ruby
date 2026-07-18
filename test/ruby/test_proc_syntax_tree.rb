# frozen_string_literal: true
require "test/unit"
require "tmpdir"

class TestProcSyntaxTree < Test::Unit::TestCase
  PRISM = RubyVM::InstructionSequence.compile("").to_a[4][:parser] == :prism

  def with_loaded_file(source)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "target.rb")
      File.write(path, source)
      load path
      yield path
    end
  end

  def test_method_ast
    with_loaded_file("def proc_ast_test_method = :ok\n") do
      node = method(:proc_ast_test_method).syntax_tree
      if PRISM
        assert_equal :def_node, node.type
        assert_equal "def proc_ast_test_method = :ok", node.slice
      else
        assert_equal :DEFN, node.type
      end
    ensure
      Object.remove_method(:proc_ast_test_method)
    end
  end

  def test_proc_ast
    with_loaded_file("PROC_AST_TEST_PROC = proc { :ok }\n") do
      node = PROC_AST_TEST_PROC.syntax_tree
      if PRISM
        assert_equal :call_node, node.type
        assert_equal "proc { :ok }", node.slice
      else
        assert_equal :ITER, node.type
      end
    ensure
      Object.send(:remove_const, :PROC_AST_TEST_PROC)
    end
  end

  def test_returns_nil_when_source_is_modified
    with_loaded_file("def proc_ast_test_modified = :ok\n") do |path|
      File.write(path, "def proc_ast_test_modified = :changed\n")
      assert_nil method(:proc_ast_test_modified).syntax_tree

      File.write(path, "def proc_ast_test_modified = (\n")
      assert_nil method(:proc_ast_test_modified).syntax_tree
    ensure
      Object.remove_method(:proc_ast_test_modified)
    end
  end

  def test_ignores_the_data_section
    with_loaded_file("def proc_ast_test_data = :ok\n__END__\noriginal\n") do |path|
      File.write(path, "def proc_ast_test_data = :ok\n__END__\nchanged\n")
      refute_nil method(:proc_ast_test_data).syntax_tree
    ensure
      Object.remove_method(:proc_ast_test_data)
    end
  end

  def test_eval_with_keep_script_lines
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      RubyVM.keep_script_lines = true
      eval("def proc_ast_test_eval_ksl = :ok\nPROC_AST_TEST_KSL = proc { :ok }\n", binding, "(eval-ksl)", 1)

      refute_nil method(:proc_ast_test_eval_ksl).syntax_tree
      refute_nil PROC_AST_TEST_KSL.syntax_tree
    end;
  end

  def test_returns_nil_for_eval
    assert_nil eval("proc { :ok }").syntax_tree
  end

  def test_returns_nil_for_c_method
    assert_nil method(:puts).syntax_tree
  end

  def test_source_hash_survives_binary_round_trip
    with_loaded_file("def proc_ast_test_binary = :ok\n") do |path|
      iseq = RubyVM::InstructionSequence.compile_file(path)
      loaded = RubyVM::InstructionSequence.load_from_binary(iseq.to_binary)

      assert_equal iseq.source_hash, loaded.source_hash
      assert_equal (PRISM ? :program_node : :SCOPE), loaded.syntax_tree.type
    end
  end

  def test_source_hash_in_to_a
    iseq = RubyVM::InstructionSequence.compile("x = 1")
    assert_equal iseq.source_hash, iseq.to_a[4][:source_hash]
  end


  def test_parse_y_syntax_tree
    assert_separately(%w[--parser=parse.y], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      require "tmpdir"
      Dir.mktmpdir do |dir|
        path = File.join(dir, "target.rb")
        File.write(path, "def proc_ast_test_parse_y = :ok\n")
        load path

        node = method(:proc_ast_test_parse_y).syntax_tree
        assert_equal RubyVM::AbstractSyntaxTree::Node, node.class
        assert_equal :DEFN, node.type

        File.write(path, "def proc_ast_test_parse_y = :changed\n")
        assert_nil method(:proc_ast_test_parse_y).syntax_tree

        File.write(path, "def proc_ast_test_parse_y = (\n")
        assert_nil method(:proc_ast_test_parse_y).syntax_tree
      end
    end;
  end
end
