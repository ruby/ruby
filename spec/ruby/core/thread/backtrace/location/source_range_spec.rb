require_relative '../../../../spec_helper'
require_relative '../../../../fixtures/source_range_helpers'

ruby_version_is "4.1" do
  describe "Thread::Backtrace::Location#source_range" do
    it "returns a Ruby::SourceRange with the location paths" do
      location, range, path, absolute_path = capture_backtrace_location_source_range(<<-RUBY)
      $nil.foo$
      RUBY

      range.should.instance_of?(Ruby::SourceRange)
      range.path.should == path
      range.absolute_path.should == absolute_path
      location.path.should == path
      location.absolute_path.should == absolute_path
    end

    {
      "receiver calls with arguments" => <<-RUBY,
      $nil.foo(42)$
      RUBY

      "receiver calls split across lines" => <<-RUBY,
      $nil
        .foo(
          42
        )$
      RUBY

      "safe navigation calls" => <<-RUBY,
      $1&.foo(42)$
      RUBY

      "special call syntax" => <<-RUBY,
      $nil.(42)$
      RUBY

      "calls to send" => <<-RUBY,
      $nil.send(:foo, 42)$
      RUBY

      "index reads" => <<-RUBY,
      $nil[0]$
      RUBY

      "index writes" => <<-RUBY,
      $nil[0] = 42$
      RUBY

      "explicit index writer calls" => <<-RUBY,
      $nil.[]=$
      RUBY

      "attribute writes" => <<-RUBY,
      $nil.foo = 42$
      RUBY

      "binary operator calls split by a comment" => <<-RUBY,
      $nil + # comment
        42$
      RUBY

      "unary operator calls" => <<-RUBY,
      $+nil$
      RUBY

      "function calls" => <<-RUBY,
      "str".instance_eval { $gsub("foo", :sym)$ }
      RUBY

      "function calls with command arguments" => <<-RUBY,
      "str".instance_eval { $gsub "foo", :sym$ }
      RUBY

      "variable calls" => <<-RUBY,
      nil.instance_eval { $foo$ }
      RUBY

      "local variable operator assignments" => <<-RUBY,
      value = nil
      $value += 42$
      RUBY

      "index operator assignments failing while reading" => <<-RUBY,
      value = nil
      $value[0] += 42$
      RUBY

      "index operator assignments failing in the operator" => <<-RUBY,
      value = Object.new
      def value.[](index) = nil
      $value[0] += 42$
      RUBY

      "index operator assignments failing while writing" => <<-RUBY,
      value = Object.new
      def value.[](index) = 1
      $value[0] += 42$
      RUBY

      "index operator assignments failing on an argument" => <<-RUBY,
      value = []
      $value[nil] += 42$
      RUBY

      "attribute operator assignments failing while reading" => <<-RUBY,
      value = nil
      $value.foo += 42$
      RUBY

      "attribute operator assignments failing in the operator" => <<-RUBY,
      value = Object.new
      def value.foo = nil
      $value.foo += 42$
      RUBY

      "attribute operator assignments failing while writing" => <<-RUBY,
      value = Object.new
      def value.foo = 1
      $value.foo += 42$
      RUBY

      "attribute operator assignments failing on the value" => <<-RUBY,
      value = Object.new
      def value.foo = 1
      def value.foo=(new_value)
        new_value
      end
      $value.foo += nil$
      RUBY

      "bare constants" => <<-RUBY,
      $SourceRangeNotDefined$
      RUBY

      "qualified constants" => <<-RUBY,
      $Object::SourceRangeNotDefined$
      RUBY

      "qualified constants split across lines" => <<-RUBY,
      $Object::
        SourceRangeNotDefined$
      RUBY

      "top-level constants" => <<-RUBY,
      $::SourceRangeNotDefined$
      RUBY

      "constant operator assignments" => <<-RUBY,
      namespace = Module.new
      namespace.const_set(:Nil, nil)
      $namespace::Nil += 1$
      RUBY

      "constant operator assignments failing while reading" => <<-RUBY,
      namespace = Module.new
      $namespace::NotDefined += 1$
      RUBY

      "top-level constant operator assignments" => <<-RUBY,
      $::SourceRangeNotDefined += 1$
      RUBY

      "explicit raises" => <<-RUBY,
      $raise NameError$
      RUBY

      "calls failing while converting arguments" => <<-RUBY,
      $1.+(nil)$
      RUBY

      "calls with brace blocks" => <<-RUBY,
      $nil.foo(1) { 2 }$
      RUBY

      "calls with do-end blocks" => <<-RUBY,
      $nil.foo(1) do
        2
      end$
      RUBY

      "calls with heredoc arguments" => <<-RUBY,
      $nil.foo(<<~TEXT)$
        heredoc
      TEXT
      RUBY

      "multibyte identifiers with byte columns" => <<-RUBY,
      value = "été"
      $value.あいうえお$
      RUBY

      "hard tabs" => "\t \t$1.time {}$\n",

      "a missing final newline" => "$1.time {}$",

      "very long source lines" => ("1" * 100) + " + $1.time {}$\n",
    }.each do |description, source|
      it "returns the precise range for #{description}" do
        capture_backtrace_location_source_range(source)
      end
    end

    it "returns the method definition for a method arity frame" do
      capture_backtrace_location_source_range(<<-RUBY)
      target = Class.new do
        $def source_range_target(first, second)
          first + second
        end$
      end.new
      target.source_range_target(1)
      RUBY
    end

    it "returns the call for the caller frame of a method arity error" do
      capture_backtrace_location_source_range(<<-RUBY, frame: 1)
      target = Class.new do
        def source_range_target(first, second)
          first + second
        end
      end.new
      $target.source_range_target(1)$
      RUBY
    end

    it "returns a multiline method definition for its arity frame" do
      capture_backtrace_location_source_range(<<-RUBY)
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

    it "returns a singleton method definition with spacing for a keyword arity frame" do
      capture_backtrace_location_source_range(<<-RUBY)
      target = Object.new
      $def target . source_range_target(value:)
        value
      end$
      target.source_range_target
      RUBY
    end

    it "returns a stabby lambda for its arity frame" do
      capture_backtrace_location_source_range(<<-RUBY)
      value = $->(argument) {}$
      value.call
      RUBY
    end

    it "returns only the block for a lambda method arity frame" do
      capture_backtrace_location_source_range(<<-RUBY)
      value = lambda ${ |argument| }$
      value.call
      RUBY
    end

    it "returns only the block for a define_method arity frame" do
      capture_backtrace_location_source_range(<<-RUBY)
      target = Class.new do
        define_method(:source_range_target) $do |first, second|
          first + second
        end$
      end.new
      target.source_range_target(1)
      RUBY
    end

    it "propagates an error when the absolute source file no longer exists" do
      keep_eval_source(false) do
        location, path = capture_backtrace_location_from_source("nil.foo\n")
        rm_r(path)

        -> {
          location.source_range
        }.should.raise(Errno::ENOENT)
      ensure
        rm_r(path) if path && File.exist?(path)
      end
    end

    it "propagates a syntax error from changed source" do
      keep_eval_source(false) do
        location, path = capture_backtrace_location_from_source("nil.foo\n")
        File.binwrite(path, "(\n")

        -> {
          location.source_range
        }.should.raise(SyntaxError)
      ensure
        rm_r(path) if path && File.exist?(path)
      end
    end

    it "raises when changed source no longer contains the node ID" do
      keep_eval_source(false) do
        location, path = capture_backtrace_location_from_source("first = 1\nsecond = 2\nnil.foo\n")
        File.binwrite(path, "nil\n")

        -> {
          location.source_range
        }.should.raise(RuntimeError, /cannot find node ID \d+ in parsed source/)
      ensure
        rm_r(path) if path && File.exist?(path)
      end
    end

    it "uses retained eval source and preserves its starting line" do
      keep_eval_source do
        path = File.realpath(__FILE__)

        location, range = capture_eval_backtrace_location_source_range(
          "$nil.foo$",
          path,
          100
        )

        range.path.should == path
        range.absolute_path.should == nil
        location.lineno.should == 100
      end
    end

    it "preserves the starting line for a block ISeq in retained eval source" do
      keep_eval_source do
        capture_eval_backtrace_location_source_range(<<-RUBY, "source_range_eval.rb", 100)
        value = lambda ${ |argument| }$
        value.call
        RUBY
      end
    end

    it "does not open an eval path even when it names an existing absolute file" do
      keep_eval_source(false) do
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
      keep_eval_source(false) do
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
      code = "eval(%q{def spoofed_source_range_target; nil.foo; end}, binding, %q{-e}); " \
        "begin; spoofed_source_range_target; rescue => e; " \
        "begin; e.backtrace_locations.first.source_range; rescue => source_error; " \
        "print source_error.class; end; end"
      ruby_exe(nil, options: "-e #{code.dump}").should == "ArgumentError"
    end

    it "works for -e source" do
      code = "def source_range_target; nil.foo; end; " \
        "begin; source_range_target; rescue => e; " \
        "r = e.backtrace_locations.first.source_range; " \
        "p [r.path, r.absolute_path, r.start_line, r.start_column, r.end_line, r.end_column]; end"
      start_column = code.byteindex("nil.foo")
      expected = ["-e", nil, 1, start_column, 1, start_column + "nil.foo".bytesize]
      ruby_exe(nil, options: "-e #{code.dump}").should == "#{expected.inspect}\n"
    end
  end
end
