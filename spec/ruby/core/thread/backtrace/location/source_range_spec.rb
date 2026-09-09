require_relative '../../../../spec_helper'
require_relative '../../../../fixtures/source_range_helpers'

ruby_version_is "4.1" do
  describe "Thread::Backtrace::Location#source_range" do
    before do
      skip "parse.y" if proc {}.syntax_tree.is_a?(RubyVM::AbstractSyntaxTree::Node)
    end

    it "returns a Ruby::SourceRange with the location paths" do
      location, range, path, absolute_path = capture_backtrace_location_source_range(<<-RUBY, :CallNode)
      $nil.foo$
      RUBY

      range.should.instance_of?(Ruby::SourceRange)
      range.path.should == path
      range.absolute_path.should == absolute_path
      location.path.should == path
      location.absolute_path.should == absolute_path
    end

    {
      "receiver calls with arguments" => [<<-RUBY, :CallNode],
      $nil.foo(42)$
      RUBY

      "receiver calls split across lines" => [<<-RUBY, :CallNode],
      $nil
        .foo(
          42
        )$
      RUBY

      "safe navigation calls" => [<<-RUBY, :CallNode],
      $1&.foo(42)$
      RUBY

      ".() call syntax" => [<<-RUBY, :CallNode],
      $nil.(42)$
      RUBY

      "calls to send" => [<<-RUBY, :CallNode],
      $nil.send(:foo, 42)$
      RUBY

      "index reads" => [<<-RUBY, :CallNode],
      $nil[0]$
      RUBY

      "index writes" => [<<-RUBY, :CallNode],
      $nil[0] = 42$
      RUBY

      "explicit index write calls" => [<<-RUBY, :CallNode],
      $nil.[]=$
      RUBY

      "attribute writes" => [<<-RUBY, :CallNode],
      $nil.foo = 42$
      RUBY

      "binary operator calls split by a comment" => [<<-RUBY, :CallNode],
      $nil + # comment
        42$
      RUBY

      "unary operator calls" => [<<-RUBY, :CallNode],
      $+nil$
      RUBY

      "function calls" => [<<-RUBY, :CallNode],
      "str".instance_eval { $gsub("foo", :sym)$ }
      RUBY

      "function calls without ()" => [<<-RUBY, :CallNode],
      "str".instance_eval { $gsub "foo", :sym$ }
      RUBY

      "variable calls" => [<<-RUBY, :CallNode],
      nil.instance_eval { $foo$ }
      RUBY

      "local variable operator assignments" => [<<-RUBY, :LocalVariableOperatorWriteNode],
      value = nil
      $value += 42$
      RUBY

      "index operator assignments failing while reading" => [<<-RUBY, :IndexOperatorWriteNode],
      value = nil
      $value[0] += 42$
      RUBY

      "index operator assignments failing in the operator" => [<<-RUBY, :IndexOperatorWriteNode],
      value = Object.new
      def value.[](index) = nil
      $value[0] += 42$
      RUBY

      "index operator assignments failing while writing" => [<<-RUBY, :IndexOperatorWriteNode],
      value = Object.new
      def value.[](index) = 1
      $value[0] += 42$
      RUBY

      "index operator assignments failing on an argument" => [<<-RUBY, :IndexOperatorWriteNode],
      value = []
      $value[nil] += 42$
      RUBY

      "attribute operator assignments failing while reading" => [<<-RUBY, :CallOperatorWriteNode],
      value = nil
      $value.foo += 42$
      RUBY

      "attribute operator assignments failing in the operator" => [<<-RUBY, :CallOperatorWriteNode],
      value = Object.new
      def value.foo = nil
      $value.foo += 42$
      RUBY

      "attribute operator assignments failing while writing" => [<<-RUBY, :CallOperatorWriteNode],
      value = Object.new
      def value.foo = 1
      $value.foo += 42$
      RUBY

      "attribute operator assignments failing on the value" => [<<-RUBY, :CallOperatorWriteNode],
      value = Object.new
      def value.foo = 1
      def value.foo=(new_value)
        new_value
      end
      $value.foo += nil$
      RUBY

      "bare constants" => [<<-RUBY, :ConstantReadNode],
      $SourceRangeNotDefined$
      RUBY

      "qualified constants" => [<<-RUBY, :ConstantPathNode],
      $Object::SourceRangeNotDefined$
      RUBY

      "qualified constants split across lines" => [<<-RUBY, :ConstantPathNode],
      $Object::
        SourceRangeNotDefined$
      RUBY

      "top-level constants" => [<<-RUBY, :ConstantPathNode],
      $::SourceRangeNotDefined$
      RUBY

      "constant operator assignments" => [<<-RUBY, :ConstantPathOperatorWriteNode],
      namespace = Module.new
      namespace.const_set(:Nil, nil)
      $namespace::Nil += 1$
      RUBY

      # This covers the whole expression for consistency with other operator assignments
      # where there is no "read node": https://bugs.ruby-lang.org/issues/22235
      "constant operator assignments failing while reading" => [<<-RUBY, :ConstantPathOperatorWriteNode],
      namespace = Module.new
      $namespace::NotDefined += 1$
      RUBY

      "top-level ::constant operator assignments" => [<<-RUBY, :ConstantPathOperatorWriteNode],
      $::SourceRangeNotDefined += 1$
      RUBY

      "top-level constant operator assignments" => [<<-RUBY, :ConstantOperatorWriteNode],
      $SourceRangeNotDefined += 1$
      RUBY

      "explicit #raise" => [<<-RUBY, :CallNode],
      $raise NameError$
      RUBY

      "calls failing while converting arguments" => [<<-RUBY, :CallNode],
      $1.+(nil)$
      RUBY

      "calls with brace blocks" => [<<-RUBY, :CallNode],
      $nil.foo(1) { 2 }$
      RUBY

      "calls with do-end blocks" => [<<-RUBY, :CallNode],
      $nil.foo(1) do
        2
      end$
      RUBY

      "calls with heredoc arguments" => [<<-RUBY, :CallNode],
      $nil.foo(<<~TEXT)$
        heredoc
      TEXT
      RUBY

      "source with a data section" => ["$nil.foo$\n__END__\ndata\n", :CallNode],

      "__END__ inside a heredoc" => ["value = <<TEXT\n__END__\nTEXT\n$nil.foo$\n", :CallNode],

      "multibyte identifiers with byte columns" => [<<-RUBY, :CallNode],
      value = "été"
      $value.あいうえお$
      RUBY

      "hard tabs" => ["\t \t$1.time {}$\n", :CallNode],

      "a missing final newline" => ["$1.time {}$", :CallNode],

      "very long source lines" => [("1" * 100) + " + $1.time {}$\n", :CallNode],

      "-> { it } called with no arguments" => [<<-RUBY, :LambdaNode],
      $-> { it }$.call()
      RUBY

      "lambda with rescue" => [<<-RUBY, :BlockNode],
      lambda $do; rescue; end$.call(1)
      RUBY

      "def with rescue" => [<<-RUBY, :DefNode],
      value = Object.new
      $def value.f(a); rescue => e; e; end$
      value.f()
      RUBY

      "block with it parameters" => [<<-RUBY, :BlockNode],
      value = lambda $do
        it
      end$
      value.call
      RUBY

      "block with numbered parameters" => [<<-RUBY, :BlockNode],
      value = lambda ${ _1 }$
      value.call
      RUBY

      "lambda with numbered parameters" => [<<-RUBY, :LambdaNode],
      value = $-> { _1 }$
      value.call
      RUBY

      "hash pattern with implicit key" => [<<-RUBY, :HashPatternNode],
      value = Object.new
      def value.deconstruct_keys(keys) = nil
      case value
      in $key:$
      end
      RUBY

      "hash pattern with value" => [<<-RUBY, :HashPatternNode],
      value = Object.new
      def value.deconstruct_keys(keys) = nil
      case value
      in $key: 1$
      end
      RUBY

      "hash pattern with rest" => [<<-RUBY, :HashPatternNode],
      value = Object.new
      def value.deconstruct_keys(keys) = nil
      case value
      in $**rest$
      end
      RUBY

      "hash pattern rejecting extra keys" => [<<-RUBY, :HashPatternNode],
      value = Object.new
      def value.deconstruct_keys(keys) = nil
      case value
      in $**nil$
      end
      RUBY

      "array pattern with splat" => [<<-RUBY, :ArrayPatternNode],
      value = Object.new
      def value.deconstruct = nil
      case value
      in $*rest$
      end
      RUBY

      "keyword hash with splat" => [<<-RUBY, :KeywordHashNode],
      value = Object.new
      def value.to_hash = 1
      [$**value$]
      RUBY

      "keyword hash with association" => [<<-RUBY, :KeywordHashNode],
      key = Object.new
      def key.hash = nil
      [$key => 1$]
      RUBY

      "array with splat" => [<<-RUBY, :ArrayNode],
      value = Object.new
      def value.to_a = 1
      result = $*value$
      RUBY

      "singleton class with rescue" => [<<-RUBY, :SingletonClassNode],
      value = 1
      $class << value; rescue; end$
      RUBY

      "class with rescue" => [<<-RUBY, :ClassNode],
      SourceRangeClassSpecs = 1
      $class SourceRangeClassSpecs; rescue; end$
      RUBY

      "module with rescue" => [<<-RUBY, :ModuleNode],
      SourceRangeModuleSpecs = 1
      $module SourceRangeModuleSpecs; rescue; end$
      RUBY

      # These nodes can own real calls, so source-range lookup cannot always exclude their classes.
      "symbol used for case equality" => [<<-RUBY, :SymbolNode, 1],
      class Symbol
        alias_method :source_range_original_case_equal, :===
        def ===(other) = raise(TypeError)
      end
      begin
        case :other
        when $:expected$
        end
      ensure
        class Symbol
          alias_method :===, :source_range_original_case_equal
          remove_method :source_range_original_case_equal
        end
      end
      RUBY

      "splat converted for a when clause" => [<<-RUBY, :SplatNode, 1],
      value = Object.new
      def value.to_a = raise(TypeError)
      case nil
      when $*value$
      end
      RUBY

      "keyword argument omission call" => [<<-RUBY, :CallNode],
      def target(**keywords) = keywords
      target($missing:$)
      RUBY

      "splat returned from a method" => [<<-RUBY, :SplatNode, 1],
      value = Object.new
      def value.to_a = raise(TypeError)
      def target(value)
        return $*value$
      end
      target(value)
      RUBY

      "symbol used for pattern matching" => [<<-RUBY, :SymbolNode, 1],
      class Symbol
        alias_method :source_range_original_case_equal, :===
        def ===(other) = raise(TypeError)
      end
      begin
        case :other
        in $:expected$
        end
      ensure
        class Symbol
          alias_method :===, :source_range_original_case_equal
          remove_method :source_range_original_case_equal
        end
      end
      RUBY

      # Aborts the test process on CRuby's CI with ZJIT
      # "interpolated symbol" => [<<-RUBY, :InterpolatedSymbolNode],
      # value = Object.new
      # def value.to_s
      #   (+"\\xFF").force_encoding(Encoding::UTF_8)
      # end
      # %I[$\#{value}$]
      # RUBY
    }.each_pair do |description, (source, prism_class, frame)|
      it "returns the precise range for #{description}" do
        capture_backtrace_location_source_range(source, prism_class, frame: frame || 0)
      end
    end

    it "returns the method definition for a method arity error" do
      capture_backtrace_location_source_range(<<-RUBY, :DefNode)
      target = Class.new do
        $def source_range_target(first, second)
          first + second
        end$
      end.new
      target.source_range_target(1)
      RUBY
    end

    it "returns the call for the caller frame of a method arity error" do
      capture_backtrace_location_source_range(<<-RUBY, :CallNode, frame: 1)
      target = Class.new do
        def source_range_target(first, second)
          first + second
        end
      end.new
      $target.source_range_target(1)$
      RUBY
    end

    it "returns a multiline method definition for a method arity error" do
      capture_backtrace_location_source_range(<<-RUBY, :DefNode)
      target = Class.new do
        $def source_range_target(
          first,
          second
        )
          first + second
        end$
      end.new
      target.source_range_target(1)
      RUBY
    end

    it "returns a singleton method definition with spacing for a keyword arity error" do
      capture_backtrace_location_source_range(<<-RUBY, :DefNode)
      target = Object.new
      $def target . source_range_target(value:)
        value
      end$
      target.source_range_target
      RUBY
    end

    it "returns a stabby lambda for an arity error" do
      capture_backtrace_location_source_range(<<-RUBY, :LambdaNode)
      value = $->(argument) {}$
      value.call
      RUBY
    end

    it "returns only the block for an arity error in a Kernel#lambda" do
      capture_backtrace_location_source_range(<<-RUBY, :BlockNode)
      value = lambda ${ |argument| }$
      value.call
      RUBY
    end

    it "returns only the block for an arity error in a define_method" do
      capture_backtrace_location_source_range(<<-RUBY, :BlockNode)
      target = Class.new do
        define_method(:source_range_target) $do |first, second|
          first + second
        end$
      end.new
      target.source_range_target(1)
      RUBY
    end

    it "propagates an error when the absolute source file no longer exists" do
      keep_source(false) do
        location, path = capture_backtrace_location_from_source("nil.foo\n")
        rm_r path

        -> {
          location.source_range
        }.should.raise(Errno::ENOENT)
      ensure
        rm_r path if path
      end
    end

    it "raises when changed source has invalid syntax" do
      keep_source(false) do
        location, path = capture_backtrace_location_from_source("nil.foo\n")
        File.binwrite(path, "(\n")

        -> {
          location.source_range
        }.should.raise(RuntimeError, "source has been modified")
      ensure
        rm_r path if path
      end
    end

    it "validates changed source before looking up the node ID" do
      keep_source(false) do
        location, path = capture_backtrace_location_from_source("first = 1\nsecond = 2\nnil.foo\n")
        File.binwrite(path, "nil\n")

        -> {
          location.source_range
        }.should.raise(RuntimeError, "source has been modified")
      ensure
        rm_r path if path
      end
    end

    it "raises when changed source has the same node ID layout" do
      keep_source(false) do
        location, path = capture_backtrace_location_from_source("nil.foo\n")
        File.binwrite(path, "nil.longer_method_name\n")

        -> {
          location.source_range
        }.should.raise(RuntimeError, "source has been modified")
      ensure
        rm_r path if path
      end
    end

    it "uses retained eval source and preserves its starting line" do
      keep_source do
        path = File.realpath(__FILE__)

        location, range = capture_eval_backtrace_location_source_range(
          "$nil.foo$",
          path,
          100
        )

        range.path.should == path
        range.absolute_path.should == nil
        range.start_line.should == 100
        location.lineno.should == 100
      end
    end

    it "preserves the starting line for blocks in retained eval source" do
      keep_source do
        location, range = capture_eval_backtrace_location_source_range(<<-RUBY, "source_range_eval.rb", 100)
        value = lambda ${ |argument| }$
        value.call
        RUBY

        range.start_line.should == 100
        location.lineno.should == 100
      end
    end

    it "does not open an eval path even when it names an existing absolute file" do
      keep_source(false) do
        path = File.realpath(__FILE__)

        exception = nil
        begin
          eval("nil.foo", binding, path)
        rescue Exception => error
          exception = error
        end

        -> {
          exception.backtrace_locations.first.source_range
        }.should.raise(ArgumentError, "cannot get source range for location in eval")
      end
    end

    it "does not treat an eval path named -e as command-line source" do
      keep_source(false) do
        exception = nil
        begin
          eval("nil.foo", binding, "-e")
        rescue Exception => error
          exception = error
        end

        -> {
          exception.backtrace_locations.first.source_range
        }.should.raise(ArgumentError, "cannot get source range for location in eval")
      end
    end

    it "does not treat a method from eval named -e as command-line source" do
      keep_source(false) do # skip if always keep source
        code = "eval(%q{def spoofed_source_range_target; nil.foo; end}, binding, %q{-e}); " \
          "begin; spoofed_source_range_target; rescue => e; " \
          "begin; e.backtrace_locations.first.source_range; rescue => source_error; " \
          "p source_error; end; end"
        ruby_exe(code, escape: false).should == "#<ArgumentError: cannot get source range for location in eval>\n"
      end
    end

    it "works for -e source" do
      code = "def source_range_target; nil.foo; end; " \
        "begin; source_range_target; rescue => e; " \
        "r = e.backtrace_locations.first.source_range; " \
        "p [r.path, r.absolute_path, r.start_line, r.start_column, r.end_line, r.end_column]; end"
      start_column = code.byteindex("nil.foo")
      expected = ["-e", nil, 1, start_column, 1, start_column + "nil.foo".bytesize]
      ruby_exe(code, escape: false).should == "#{expected.inspect}\n"
    end
  end
end
