# frozen_string_literal: false
require "pathname"
require "irb"

require_relative "helper"

module TestIRB
  class CompletionTest < TestCase
    def completion_candidates(target, bind)
      IRB::RegexpCompletor.new.completion_candidates('', target, '', bind: bind)
    end

    def doc_namespace(target, bind)
      IRB::RegexpCompletor.new.doc_namespace('', target, '', bind: bind)
    end

    class CommandCompletionTest < CompletionTest
      def test_command_completion
        assert_include(IRB::RegexpCompletor.new.completion_candidates('', 'show_s', '', bind: binding), 'show_source')
        assert_not_include(IRB::RegexpCompletor.new.completion_candidates(';', 'show_s', '', bind: binding), 'show_source')
      end
    end

    class MethodCompletionTest < CompletionTest
      def test_complete_string
        assert_include(completion_candidates("'foo'.up", binding), "'foo'.upcase")
        # completing 'foo bar'.up
        assert_include(completion_candidates("bar'.up", binding), "bar'.upcase")
        assert_equal("String.upcase", doc_namespace("'foo'.upcase", binding))
      end

      def test_complete_regexp
        assert_include(completion_candidates("/foo/.ma", binding), "/foo/.match")
        # completing /foo bar/.ma
        assert_include(completion_candidates("bar/.ma", binding), "bar/.match")
        assert_equal("Regexp.match", doc_namespace("/foo/.match", binding))
      end

      def test_complete_array
        assert_include(completion_candidates("[].an", binding), "[].any?")
        assert_equal("Array.any?", doc_namespace("[].any?", binding))
      end

      def test_complete_hash_and_proc
        # hash
        assert_include(completion_candidates("{}.an", binding), "{}.any?")
        assert_equal(["Hash.any?", "Proc.any?"], doc_namespace("{}.any?", binding))

        # proc
        assert_include(completion_candidates("{}.bin", binding), "{}.binding")
        assert_equal(["Hash.binding", "Proc.binding"], doc_namespace("{}.binding", binding))
      end

      def test_complete_numeric
        assert_include(completion_candidates("1.positi", binding), "1.positive?")
        assert_equal("Integer.positive?", doc_namespace("1.positive?", binding))

        assert_include(completion_candidates("1r.positi", binding), "1r.positive?")
        assert_equal("Rational.positive?", doc_namespace("1r.positive?", binding))

        assert_include(completion_candidates("0xFFFF.positi", binding), "0xFFFF.positive?")
        assert_equal("Integer.positive?", doc_namespace("0xFFFF.positive?", binding))

        assert_empty(completion_candidates("1i.positi", binding))
      end

      def test_complete_symbol
        assert_include(completion_candidates(":foo.to_p", binding), ":foo.to_proc")
        assert_equal("Symbol.to_proc", doc_namespace(":foo.to_proc", binding))
      end

      def test_complete_class
        assert_include(completion_candidates("String.ne", binding), "String.new")
        assert_equal("String.new", doc_namespace("String.new", binding))
      end
    end

    class RequireComepletionTest < CompletionTest
      def test_complete_require
        candidates = IRB::RegexpCompletor.new.completion_candidates("require ", "'irb", "", bind: binding)
        %w['irb/init 'irb/ruby-lex].each do |word|
          assert_include candidates, word
        end
        # Test cache
        candidates = IRB::RegexpCompletor.new.completion_candidates("require ", "'irb", "", bind: binding)
        %w['irb/init 'irb/ruby-lex].each do |word|
          assert_include candidates, word
        end
        # Test string completion not disturbed by require completion
        candidates = IRB::RegexpCompletor.new.completion_candidates("'string ", "'.", "", bind: binding)
        assert_include candidates, "'.upcase"
      end

      def test_complete_require_with_pathname_in_load_path
        temp_dir = Dir.mktmpdir
        File.write(File.join(temp_dir, "foo.rb"), "test")
        test_path = Pathname.new(temp_dir)
        $LOAD_PATH << test_path

        candidates = IRB::RegexpCompletor.new.completion_candidates("require ", "'foo", "", bind: binding)
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

        candidates = IRB::RegexpCompletor.new.completion_candidates("require ", "'foo", "", bind: binding)
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
          IRB::RegexpCompletor.new.completion_candidates("require ", "'foo", "", bind: binding)
        end
      ensure
        $LOAD_PATH.pop if object
      end

      def test_complete_require_library_name_first
        # Test that library name is completed first with subdirectories
        candidates = IRB::RegexpCompletor.new.completion_candidates("require ", "'irb", "", bind: binding)
        assert_equal "'irb", candidates.first
      end

      def test_complete_require_relative
        candidates = Dir.chdir(__dir__ + "/../..") do
          IRB::RegexpCompletor.new.completion_candidates("require_relative ", "'lib/irb", "", bind: binding)
        end
        %w['lib/irb/init 'lib/irb/ruby-lex].each do |word|
          assert_include candidates, word
        end
        # Test cache
        candidates = Dir.chdir(__dir__ + "/../..") do
          IRB::RegexpCompletor.new.completion_candidates("require_relative ", "'lib/irb", "", bind: binding)
        end
        %w['lib/irb/init 'lib/irb/ruby-lex].each do |word|
          assert_include candidates, word
        end
      end
    end

    class VariableCompletionTest < CompletionTest
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

        assert_include(completion_candidates("str_examp", binding), "str_example")
        assert_equal("String", doc_namespace("str_example", binding))
        assert_equal("String.to_s", doc_namespace("str_example.to_s", binding))

        assert_include(completion_candidates("@str_examp", binding), "@str_example")
        assert_equal("String", doc_namespace("@str_example", binding))
        assert_equal("String.to_s", doc_namespace("@str_example.to_s", binding))
      end

      def test_complete_sort_variables
        xzy, xzy_1, xzy2 = '', '', ''

        xzy.clear
        xzy_1.clear
        xzy2.clear

        candidates = completion_candidates("xz", binding)
        assert_equal(%w[xzy xzy2 xzy_1], candidates)
      end
    end

    class ConstantCompletionTest < CompletionTest
      class Foo
        B3 = 1
        B1 = 1
        B2 = 1
      end

      def test_complete_constants
        assert_equal(["Foo"], completion_candidates("Fo", binding))
        assert_equal(["Foo::B1", "Foo::B2", "Foo::B3"], completion_candidates("Foo::B", binding))
        assert_equal(["Foo::B1.positive?"], completion_candidates("Foo::B1.pos", binding))

        assert_equal(["::Forwardable"], completion_candidates("::Fo", binding))
        assert_equal("Forwardable", doc_namespace("::Forwardable", binding))
      end
    end

    def test_not_completing_empty_string
      assert_equal([], completion_candidates("", binding))
      assert_equal([], completion_candidates(" ", binding))
      assert_equal([], completion_candidates("\t", binding))
      assert_equal(nil, doc_namespace("", binding))
    end

    def test_complete_symbol
      symbols = %w"UTF-16LE UTF-7".map do |enc|
        "K".force_encoding(enc).to_sym
      rescue
      end
      symbols += [:aiueo, :"aiu eo"]
      candidates = completion_candidates(":a", binding)
      assert_include(candidates, ":aiueo")
      assert_not_include(candidates, ":aiu eo")
      assert_empty(completion_candidates(":irb_unknown_symbol_abcdefg", binding))
      # Do not complete empty symbol for performance reason
      assert_empty(completion_candidates(":", binding))
    end

    def test_complete_invalid_three_colons
      assert_empty(completion_candidates(":::A", binding))
      assert_empty(completion_candidates(":::", binding))
    end

    def test_complete_absolute_constants_with_special_characters
      assert_empty(completion_candidates("::A:", binding))
      assert_empty(completion_candidates("::A.", binding))
      assert_empty(completion_candidates("::A(", binding))
      assert_empty(completion_candidates("::A)", binding))
      assert_empty(completion_candidates("::A[", binding))
    end

    def test_complete_reserved_words
      candidates = completion_candidates("de", binding)
      %w[def defined?].each do |word|
        assert_include candidates, word
      end

      candidates = completion_candidates("__", binding)
      %w[__ENCODING__ __LINE__ __FILE__].each do |word|
        assert_include candidates, word
      end
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

      assert_include(completion_candidates("public_hog", bind), "public_hoge")
      assert_include(doc_namespace("public_hoge", bind), "public_hoge")

      assert_include(completion_candidates("private_hog", bind), "private_hoge")
      assert_include(doc_namespace("private_hoge", bind), "private_hoge")
    end
  end

  class DeprecatedInputCompletorTest < TestCase
    def setup
      save_encodings
      @verbose, $VERBOSE = $VERBOSE, nil
      IRB.init_config(nil)
      IRB.conf[:VERBOSE] = false
      IRB.conf[:MAIN_CONTEXT] = IRB::Context.new(IRB::WorkSpace.new(binding))
    end

    def teardown
      restore_encodings
      $VERBOSE = @verbose
    end

    def test_completion_proc
      assert_include(IRB::InputCompletor::CompletionProc.call('1.ab'), '1.abs')
      assert_include(IRB::InputCompletor::CompletionProc.call('1.ab', '', ''), '1.abs')
    end

    def test_retrieve_completion_data
      assert_include(IRB::InputCompletor.retrieve_completion_data('1.ab'), '1.abs')
      assert_equal(IRB::InputCompletor.retrieve_completion_data('1.abs', doc_namespace: true), 'Integer.abs')
      bind = eval('a = 1; binding')
      assert_include(IRB::InputCompletor.retrieve_completion_data('a.ab', bind: bind), 'a.abs')
      assert_equal(IRB::InputCompletor.retrieve_completion_data('a.abs', bind: bind, doc_namespace: true), 'Integer.abs')
    end
  end
end
