# frozen_string_literal: false
require "test/unit"
require "pathname"
require "irb"

module TestIRB
  class TestCompletion < Test::Unit::TestCase
    def setup
      # make sure require completion candidates are not cached
      IRB::InputCompletor.class_variable_set(:@@files_from_load_path, nil)
    end

    def test_nonstring_module_name
      begin
        require "irb/completion"
        bug5938 = '[ruby-core:42244]'
        bundle_exec = ENV.key?('BUNDLE_GEMFILE') ? ['-rbundler/setup'] : []
        cmds = bundle_exec + %W[-W0 -rirb -rirb/completion -e IRB.setup(__FILE__)
         -e IRB.conf[:MAIN_CONTEXT]=IRB::Irb.new.context
         -e module\sFoo;def\sself.name;//;end;end
         -e IRB::InputCompletor::CompletionProc.call("[1].first.")
         -- -f --]
        status = assert_in_out_err(cmds, "", //, [], bug5938)
        assert(status.success?, bug5938)
      rescue LoadError
        pend "cannot load irb/completion"
      end
    end

    def test_complete_numeric
      assert_include(IRB::InputCompletor.retrieve_completion_data("1r.positi", bind: binding), "1r.positive?")
      assert_empty(IRB::InputCompletor.retrieve_completion_data("1i.positi", bind: binding))
    end

    def test_complete_symbol
      %w"UTF-16LE UTF-7".each do |enc|
        "K".force_encoding(enc).to_sym
      rescue
      end
      _ = :aiueo
      assert_include(IRB::InputCompletor.retrieve_completion_data(":a", bind: binding), ":aiueo")
      assert_empty(IRB::InputCompletor.retrieve_completion_data(":irb_unknown_symbol_abcdefg", bind: binding))
    end

    def test_complete_invalid_three_colons
      assert_empty(IRB::InputCompletor.retrieve_completion_data(":::A", bind: binding))
      assert_empty(IRB::InputCompletor.retrieve_completion_data(":::", bind: binding))
    end

    def test_complete_absolute_constants_with_special_characters
      assert_empty(IRB::InputCompletor.retrieve_completion_data("::A:", bind: binding))
      assert_empty(IRB::InputCompletor.retrieve_completion_data("::A.", bind: binding))
      assert_empty(IRB::InputCompletor.retrieve_completion_data("::A(", bind: binding))
      assert_empty(IRB::InputCompletor.retrieve_completion_data("::A)", bind: binding))
    end

    def test_complete_symbol_failure
      assert_nil(IRB::InputCompletor::PerfectMatchedProc.(":aiueo", bind: binding))
    end

    def test_complete_reserved_words
      candidates = IRB::InputCompletor.retrieve_completion_data("de", bind: binding)
      %w[def defined?].each do |word|
        assert_include candidates, word
      end

      candidates = IRB::InputCompletor.retrieve_completion_data("__", bind: binding)
      %w[__ENCODING__ __LINE__ __FILE__].each do |word|
        assert_include candidates, word
      end
    end

    def test_complete_predicate?
      candidates = IRB::InputCompletor.retrieve_completion_data("1.posi", bind: binding)
      assert_include candidates, '1.positive?'

      namespace = IRB::InputCompletor.retrieve_completion_data("1.positive?", bind: binding, doc_namespace: true)
      assert_equal "Integer.positive?", namespace
    end

    def test_complete_require
      candidates = IRB::InputCompletor::CompletionProc.("'irb", "require ", "")
      %w['irb/init 'irb/ruby-lex].each do |word|
        assert_include candidates, word
      end
      # Test cache
      candidates = IRB::InputCompletor::CompletionProc.("'irb", "require ", "")
      %w['irb/init 'irb/ruby-lex].each do |word|
        assert_include candidates, word
      end
    end

    def test_complete_require_with_pathname_in_load_path
      temp_dir = Dir.mktmpdir
      File.write(File.join(temp_dir, "foo.rb"), "test")
      test_path = Pathname.new(temp_dir)
      $LOAD_PATH << test_path

      candidates = IRB::InputCompletor::CompletionProc.("'foo", "require ", "")
      assert_include candidates, "'foo"
    ensure
      $LOAD_PATH.pop if test_path
      FileUtils.remove_entry(temp_dir) if temp_dir
    end

    def test_complete_require_with_string_convertable_in_load_path
      temp_dir = Dir.mktmpdir
      File.write(File.join(temp_dir, "foo.rb"), "test")
      object = Object.new
      object.define_singleton_method(:to_s) { temp_dir }
      $LOAD_PATH << object

      candidates = IRB::InputCompletor::CompletionProc.("'foo", "require ", "")
      assert_include candidates, "'foo"
    ensure
      $LOAD_PATH.pop if object
      FileUtils.remove_entry(temp_dir) if temp_dir
    end

    def test_complete_require_with_malformed_object_in_load_path
      object = Object.new
      def object.to_s; raise; end
      $LOAD_PATH << object

      assert_nothing_raised do
        IRB::InputCompletor::CompletionProc.("'foo", "require ", "")
      end
    ensure
      $LOAD_PATH.pop if object
    end

    def test_complete_require_library_name_first
      pend 'Need to use virtual library paths'
      candidates = IRB::InputCompletor::CompletionProc.("'csv", "require ", "")
      assert_equal "'csv", candidates.first
    end

    def test_complete_require_relative
      candidates = Dir.chdir(__dir__ + "/../..") do
        IRB::InputCompletor::CompletionProc.("'lib/irb", "require_relative ", "")
      end
      %w['lib/irb/init 'lib/irb/ruby-lex].each do |word|
        assert_include candidates, word
      end
      # Test cache
      candidates = Dir.chdir(__dir__ + "/../..") do
        IRB::InputCompletor::CompletionProc.("'lib/irb", "require_relative ", "")
      end
      %w['lib/irb/init 'lib/irb/ruby-lex].each do |word|
        assert_include candidates, word
      end
    end

    def test_complete_variable
      # Bug fix issues https://github.com/ruby/irb/issues/368
      # Variables other than `str_example` and `@str_example` are defined to ensure that irb completion does not cause unintended behavior
      str_example = ''
      @str_example = ''
      private_methods = ''
      methods = ''
      global_variables = ''
      local_variables = ''
      instance_variables = ''

      # suppress "assigned but unused variable" warning
      str_example.clear
      @str_example.clear
      private_methods.clear
      methods.clear
      global_variables.clear
      local_variables.clear
      instance_variables.clear

      assert_include(IRB::InputCompletor.retrieve_completion_data("str_examp", bind: binding), "str_example")
      assert_equal(IRB::InputCompletor.retrieve_completion_data("str_example", bind: binding, doc_namespace: true), "String")
      assert_equal(IRB::InputCompletor.retrieve_completion_data("str_example.to_s", bind: binding, doc_namespace: true), "String.to_s")

      assert_include(IRB::InputCompletor.retrieve_completion_data("@str_examp", bind: binding), "@str_example")
      assert_equal(IRB::InputCompletor.retrieve_completion_data("@str_example", bind: binding, doc_namespace: true), "String")
      assert_equal(IRB::InputCompletor.retrieve_completion_data("@str_example.to_s", bind: binding, doc_namespace: true), "String.to_s")
    end

    def test_complete_methods
      obj = Object.new
      obj.singleton_class.class_eval {
        def public_hoge; end
        private def private_hoge; end

        # Support for overriding #methods etc.
        def methods; end
        def private_methods; end
        def global_variables; end
        def local_variables; end
        def instance_variables; end
      }
      bind = obj.instance_exec { binding }

      assert_include(IRB::InputCompletor.retrieve_completion_data("public_hog", bind: bind), "public_hoge")
      assert_include(IRB::InputCompletor.retrieve_completion_data("public_hoge.to_s", bind: bind), "public_hoge.to_s")
      assert_include(IRB::InputCompletor.retrieve_completion_data("public_hoge", bind: bind, doc_namespace: true), "public_hoge")

      assert_include(IRB::InputCompletor.retrieve_completion_data("private_hog", bind: bind), "private_hoge")
      assert_include(IRB::InputCompletor.retrieve_completion_data("private_hoge.to_s", bind: bind), "private_hoge.to_s")
      assert_include(IRB::InputCompletor.retrieve_completion_data("private_hoge", bind: bind, doc_namespace: true), "private_hoge")
    end

    def test_complete_class_method
      assert_include(IRB::InputCompletor.retrieve_completion_data("String.new", bind: binding), "String.new")
      assert_equal(IRB::InputCompletor.retrieve_completion_data("String.new", bind: binding, doc_namespace: true), "String.new")
    end

    def test_complete_sort_variables
      xzy, xzy_1, xzy2 = '', '', ''

      xzy.clear
      xzy_1.clear
      xzy2.clear

      candidates = IRB::InputCompletor.retrieve_completion_data("xz", bind: binding, doc_namespace: false)
      assert_equal(candidates, %w[xzy xzy2 xzy_1])
    end
  end
end
