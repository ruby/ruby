# frozen_string_literal: false
require "pathname"
require "irb"

require_relative "helper"

module TestIRB
  class TestCompletion < TestCase
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

    class TestMethodCompletion < TestCompletion
      def test_complete_string
        assert_include(IRB::InputCompletor.retrieve_completion_data("'foo'.up", bind: binding), "'foo'.upcase")
        assert_equal("String.upcase", IRB::InputCompletor.retrieve_completion_data("'foo'.upcase", bind: binding, doc_namespace: true))
      end

      def test_complete_regexp
        assert_include(IRB::InputCompletor.retrieve_completion_data("/foo/.ma", bind: binding), "/foo/.match")
        assert_equal("Regexp.match", IRB::InputCompletor.retrieve_completion_data("/foo/.match", bind: binding, doc_namespace: true))
      end

      def test_complete_array
        assert_include(IRB::InputCompletor.retrieve_completion_data("[].an", bind: binding), "[].any?")
        assert_equal("Array.any?", IRB::InputCompletor.retrieve_completion_data("[].any?", bind: binding, doc_namespace: true))
      end

      def test_complete_hash_and_proc
        # hash
        assert_include(IRB::InputCompletor.retrieve_completion_data("{}.an", bind: binding), "{}.any?")
        assert_equal(["Proc.any?", "Hash.any?"], IRB::InputCompletor.retrieve_completion_data("{}.any?", bind: binding, doc_namespace: true))

        # proc
        assert_include(IRB::InputCompletor.retrieve_completion_data("{}.bin", bind: binding), "{}.binding")
        assert_equal(["Proc.binding", "Hash.binding"], IRB::InputCompletor.retrieve_completion_data("{}.binding", bind: binding, doc_namespace: true))
      end

      def test_complete_numeric
        assert_include(IRB::InputCompletor.retrieve_completion_data("1.positi", bind: binding), "1.positive?")
        assert_equal("Integer.positive?", IRB::InputCompletor.retrieve_completion_data("1.positive?", bind: binding, doc_namespace: true))

        assert_include(IRB::InputCompletor.retrieve_completion_data("1r.positi", bind: binding), "1r.positive?")
        assert_equal("Rational.positive?", IRB::InputCompletor.retrieve_completion_data("1r.positive?", bind: binding, doc_namespace: true))

        assert_include(IRB::InputCompletor.retrieve_completion_data("0xFFFF.positi", bind: binding), "0xFFFF.positive?")
        assert_equal("Integer.positive?", IRB::InputCompletor.retrieve_completion_data("0xFFFF.positive?", bind: binding, doc_namespace: true))

        assert_empty(IRB::InputCompletor.retrieve_completion_data("1i.positi", bind: binding))
      end

      def test_complete_symbol
        assert_include(IRB::InputCompletor.retrieve_completion_data(":foo.to_p", bind: binding), ":foo.to_proc")
        assert_equal("Symbol.to_proc", IRB::InputCompletor.retrieve_completion_data(":foo.to_proc", bind: binding, doc_namespace: true))
      end

      def test_complete_class
        assert_include(IRB::InputCompletor.retrieve_completion_data("String.ne", bind: binding), "String.new")
        assert_equal("String.new", IRB::InputCompletor.retrieve_completion_data("String.new", bind: binding, doc_namespace: true))
      end
    end

    class TestRequireComepletion < TestCompletion
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
    end

    class TestVariableCompletion < TestCompletion
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
        assert_equal("String", IRB::InputCompletor.retrieve_completion_data("str_example", bind: binding, doc_namespace: true))
        assert_equal("String.to_s", IRB::InputCompletor.retrieve_completion_data("str_example.to_s", bind: binding, doc_namespace: true))

        assert_include(IRB::InputCompletor.retrieve_completion_data("@str_examp", bind: binding), "@str_example")
        assert_equal("String", IRB::InputCompletor.retrieve_completion_data("@str_example", bind: binding, doc_namespace: true))
        assert_equal("String.to_s", IRB::InputCompletor.retrieve_completion_data("@str_example.to_s", bind: binding, doc_namespace: true))
      end

      def test_complete_sort_variables
        xzy, xzy_1, xzy2 = '', '', ''

        xzy.clear
        xzy_1.clear
        xzy2.clear

        candidates = IRB::InputCompletor.retrieve_completion_data("xz", bind: binding, doc_namespace: false)
        assert_equal(%w[xzy xzy2 xzy_1], candidates)
      end
    end

    class TestConstantCompletion < TestCompletion
      class Foo
        B3 = 1
        B1 = 1
        B2 = 1
      end

      def test_complete_constants
        assert_equal(["Foo"], IRB::InputCompletor.retrieve_completion_data("Fo", bind: binding))
        assert_equal(["Foo::B1", "Foo::B2", "Foo::B3"], IRB::InputCompletor.retrieve_completion_data("Foo::B", bind: binding))
        assert_equal(["Foo::B1.positive?"], IRB::InputCompletor.retrieve_completion_data("Foo::B1.pos", bind: binding))

        assert_equal(["::Forwardable"], IRB::InputCompletor.retrieve_completion_data("::Fo", bind: binding))
        assert_equal("Forwardable", IRB::InputCompletor.retrieve_completion_data("::Forwardable", bind: binding, doc_namespace: true))
      end
    end

    class TestPerfectMatching < TestCompletion
      def setup
        # trigger PerfectMatchedProc to set up RDocRIDriver constant
        IRB::InputCompletor::PerfectMatchedProc.("foo", bind: binding)

        @original_use_stdout = IRB::InputCompletor::RDocRIDriver.use_stdout
        # force the driver to use stdout so it doesn't start a pager and interrupt tests
        IRB::InputCompletor::RDocRIDriver.use_stdout = true
      end

      def teardown
        IRB::InputCompletor::RDocRIDriver.use_stdout = @original_use_stdout
      end

      def test_perfectly_matched_namespace_triggers_document_display
        omit unless has_rdoc_content?

        out, err = capture_output do
          IRB::InputCompletor::PerfectMatchedProc.("String", bind: binding)
        end

        assert_empty(err)

        assert_include(out, " S\bSt\btr\bri\bin\bng\bg")
      end

      def test_perfectly_matched_multiple_namespaces_triggers_document_display
        result = nil
        out, err = capture_output do
          result = IRB::InputCompletor::PerfectMatchedProc.("{}.nil?", bind: binding)
        end

        assert_empty(err)

        # check if there're rdoc contents (e.g. CI doesn't generate them)
        if has_rdoc_content?
          # if there's rdoc content, we can verify by checking stdout
          # rdoc generates control characters for formatting method names
          assert_include(out, "P\bPr\bro\boc\bc.\b.n\bni\bil\bl?\b?") # Proc.nil?
          assert_include(out, "H\bHa\bas\bsh\bh.\b.n\bni\bil\bl?\b?") # Hash.nil?
        else
          # this is a hacky way to verify the rdoc rendering code path because CI doesn't have rdoc content
          # if there are multiple namespaces to be rendered, PerfectMatchedProc renders the result with a document
          # which always returns the bytes rendered, even if it's 0
          assert_equal(0, result)
        end
      end

      def test_not_matched_namespace_triggers_nothing
        result = nil
        out, err = capture_output do
          result = IRB::InputCompletor::PerfectMatchedProc.("Stri", bind: binding)
        end

        assert_empty(err)
        assert_empty(out)
        assert_nil(result)
      end

      def test_perfect_matching_stops_without_rdoc
        result = nil

        out, err = capture_output do
          without_rdoc do
            result = IRB::InputCompletor::PerfectMatchedProc.("String", bind: binding)
          end
        end

        assert_empty(err)
        assert_not_match(/from ruby core/, out)
        assert_nil(result)
      end

      def test_perfect_matching_handles_nil_namespace
        out, err = capture_output do
          # symbol literal has `nil` doc namespace so it's a good test subject
          assert_nil(IRB::InputCompletor::PerfectMatchedProc.(":aiueo", bind: binding))
        end

        assert_empty(err)
        assert_empty(out)
      end

      private

      def has_rdoc_content?
        File.exist?(RDoc::RI::Paths::BASE)
      end
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
  end
end
