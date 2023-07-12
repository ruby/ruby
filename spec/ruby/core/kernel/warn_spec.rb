require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#warn" do
  before :each do
    @before_verbose = $VERBOSE
    @before_separator = $/
  end

  after :each do
    $VERBOSE = nil
    $/ = @before_separator
    $VERBOSE = @before_verbose
  end

  it "is a private method" do
    Kernel.should have_private_instance_method(:warn)
  end

  it "accepts multiple arguments" do
    Kernel.method(:warn).arity.should < 0
  end

  it "does not append line-end if last character is line-end" do
    -> {
      $VERBOSE = true
      warn("this is some simple text with line-end\n")
    }.should output(nil, "this is some simple text with line-end\n")
  end

  it "calls #write on $stderr if $VERBOSE is true" do
    -> {
      $VERBOSE = true
      warn("this is some simple text")
    }.should output(nil, "this is some simple text\n")
  end

  it "calls #write on $stderr if $VERBOSE is false" do
    -> {
      $VERBOSE = false
      warn("this is some simple text")
    }.should output(nil, "this is some simple text\n")
  end

  it "does not call #write on $stderr if $VERBOSE is nil" do
    -> {
      $VERBOSE = nil
      warn("this is some simple text")
    }.should output(nil, "")
  end

  it "writes each argument on a line when passed multiple arguments" do
    -> {
      $VERBOSE = true
      warn("line 1", "line 2")
    }.should output(nil, "line 1\nline 2\n")
  end

  it "writes each array element on a line when passes an array" do
    -> {
      $VERBOSE = true
      warn(["line 1", "line 2"])
    }.should output(nil, "line 1\nline 2\n")
  end

  it "does not write strings when passed no arguments" do
    -> {
      $VERBOSE = true
      warn
    }.should output("", "")
  end

  it "writes the default record separator and NOT $/ to $stderr after the warning message" do
    -> {
      $VERBOSE = true
      $/ = 'rs'
      warn("")
    }.should output(nil, /\n/)
  end

  it "writes to_s representation if passed a non-string" do
    obj = mock("obj")
    obj.should_receive(:to_s).and_return("to_s called")
    -> {
      $VERBOSE = true
      warn(obj)
    }.should output(nil, "to_s called\n")
  end

  describe ":uplevel keyword argument" do
    before :each do
      $VERBOSE = true
    end

    it "prepends a message with specified line from the backtrace" do
      w = KernelSpecs::WarnInNestedCall.new

      -> { w.f4("foo", 0) }.should output(nil, %r|core/kernel/fixtures/classes.rb:#{w.warn_call_lineno}: warning: foo|)
      -> { w.f4("foo", 1) }.should output(nil, %r|core/kernel/fixtures/classes.rb:#{w.f1_call_lineno}: warning: foo|)
      -> { w.f4("foo", 2) }.should output(nil, %r|core/kernel/fixtures/classes.rb:#{w.f2_call_lineno}: warning: foo|)
      -> { w.f4("foo", 3) }.should output(nil, %r|core/kernel/fixtures/classes.rb:#{w.f3_call_lineno}: warning: foo|)
    end

    # Test both explicitly without and with RubyGems as RubyGems overrides Kernel#warn
    it "shows the caller of #require and not #require itself without RubyGems" do
      file = fixture(__FILE__ , "warn_require_caller.rb")
      ruby_exe(file, options: "--disable-gems", args: "2>&1").should == "#{file}:2: warning: warn-require-warning\n"
    end

    it "shows the caller of #require and not #require itself with RubyGems loaded" do
      file = fixture(__FILE__ , "warn_require_caller.rb")
      ruby_exe(file, options: "-rrubygems", args: "2>&1").should == "#{file}:2: warning: warn-require-warning\n"
    end

    guard -> { Kernel.instance_method(:tap).source_location } do
      it "skips <internal: core library methods defined in Ruby" do
        file, line = Kernel.instance_method(:tap).source_location
        file.should.start_with?('<internal:')

        file = fixture(__FILE__ , "warn_core_method.rb")
        n = 9
        ruby_exe(file, options: "--disable-gems", args: "2>&1").lines.should == [
          "#{file}:#{n+0}: warning: use X instead\n",
          "#{file}:#{n+1}: warning: use X instead\n",
          "#{file}:#{n+2}: warning: use X instead\n",
          "#{file}:#{n+4}: warning: use X instead\n",
        ]
      end
    end

    it "accepts :category keyword with a symbol" do
      -> {
        $VERBOSE = true
        warn("message", category: :deprecated)
      }.should output(nil, "message\n")
    end

    it "accepts :category keyword with nil" do
      -> {
        $VERBOSE = true
        warn("message", category: nil)
      }.should output(nil, "message\n")
    end

    it "accepts :category keyword with object convertible to symbol" do
      o = Object.new
      def o.to_sym; :deprecated; end
      -> {
        $VERBOSE = true
        warn("message", category: o)
      }.should output(nil, "message\n")
    end

    it "raises if :category keyword is not nil and not convertible to symbol" do
      -> {
        $VERBOSE = true
        warn("message", category: Object.new)
      }.should raise_error(TypeError)
    end

    it "converts first arg using to_s" do
      w = KernelSpecs::WarnInNestedCall.new

      -> { w.f4(false, 0) }.should output(nil, %r|core/kernel/fixtures/classes.rb:#{w.warn_call_lineno}: warning: false|)
      -> { w.f4(nil, 1) }.should output(nil, %r|core/kernel/fixtures/classes.rb:#{w.f1_call_lineno}: warning: |)
      obj = mock("obj")
      obj.should_receive(:to_s).and_return("to_s called")
      -> { w.f4(obj, 2) }.should output(nil, %r|core/kernel/fixtures/classes.rb:#{w.f2_call_lineno}: warning: to_s called|)
    end

    it "does not prepend caller information if the uplevel argument is too large" do
      w = KernelSpecs::WarnInNestedCall.new
      -> { w.f4("foo", 100) }.should output(nil, "warning: foo\n")
    end

    it "prepends even if a message is empty or nil" do
      w = KernelSpecs::WarnInNestedCall.new

      -> { w.f4("", 0) }.should output(nil, %r|core/kernel/fixtures/classes.rb:#{w.warn_call_lineno}: warning: \n$|)
      -> { w.f4(nil, 0) }.should output(nil, %r|core/kernel/fixtures/classes.rb:#{w.warn_call_lineno}: warning: \n$|)
    end

    it "converts value to Integer" do
      w = KernelSpecs::WarnInNestedCall.new

      -> { w.f4(0.1) }.should output(nil, %r|classes.rb:#{w.warn_call_lineno}:|)
      -> { w.f4(Rational(1, 2)) }.should output(nil, %r|classes.rb:#{w.warn_call_lineno}:|)
    end

    it "raises ArgumentError if passed negative value" do
      -> { warn "", uplevel: -2 }.should raise_error(ArgumentError)
      -> { warn "", uplevel: -100 }.should raise_error(ArgumentError)
    end

    it "raises ArgumentError if passed -1" do
      -> { warn "", uplevel: -1 }.should raise_error(ArgumentError)
    end

    it "raises TypeError if passed not Integer" do
      -> { warn "", uplevel: "" }.should raise_error(TypeError)
      -> { warn "", uplevel: [] }.should raise_error(TypeError)
      -> { warn "", uplevel: {} }.should raise_error(TypeError)
      -> { warn "", uplevel: Object.new }.should raise_error(TypeError)
    end
  end

  it "treats empty hash as no keyword argument" do
    h = {}
    -> { warn(**h) }.should_not complain(verbose: true)
    -> { warn('foo', **h) }.should complain("foo\n")
  end

  it "calls Warning.warn without keyword arguments if Warning.warn does not accept keyword arguments" do
    verbose = $VERBOSE
    $VERBOSE = false
    class << Warning
      alias_method :_warn, :warn
      def warn(message)
        ScratchPad.record(message)
      end
    end

    begin
      ScratchPad.clear
      Kernel.warn("Chunky bacon!")
      ScratchPad.recorded.should == "Chunky bacon!\n"

      Kernel.warn("Deprecated bacon!", category: :deprecated)
      ScratchPad.recorded.should == "Deprecated bacon!\n"
    ensure
      class << Warning
        remove_method :warn
        alias_method :warn, :_warn
        remove_method :_warn
      end
      $VERBOSE = verbose
    end
  end

  it "calls Warning.warn with category: nil if Warning.warn accepts keyword arguments" do
    Warning.should_receive(:warn).with("Chunky bacon!\n", category: nil)
    verbose = $VERBOSE
    $VERBOSE = false
    begin
      Kernel.warn("Chunky bacon!")
    ensure
      $VERBOSE = verbose
    end
  end

  it "calls Warning.warn with given category keyword converted to a symbol" do
    Warning.should_receive(:warn).with("Chunky bacon!\n", category: :deprecated)
    verbose = $VERBOSE
    $VERBOSE = false
    begin
      Kernel.warn("Chunky bacon!", category: 'deprecated')
    ensure
      $VERBOSE = verbose
    end
  end

  it "does not call Warning.warn if self is the Warning module" do
    # RubyGems redefines Kernel#warn so we need to use a subprocess and disable RubyGems here
    code = <<-RUBY
    def Warning.warn(*args, **kwargs)
      raise 'should not be called'
    end
    Kernel.instance_method(:warn).bind(Warning).call('Kernel#warn spec edge case')
    RUBY
    out = ruby_exe(code, args: "2>&1", options: "--disable-gems")
    out.should == "Kernel#warn spec edge case\n"
    $?.should.success?
  end

  it "avoids recursion if Warning#warn is redefined and calls super" do
    # This works because of the spec above, which is the workaround for it.
    # Note that redefining Warning#warn is a mistake which would naturally end in infinite recursion,
    # Warning.extend Module.new { def warn } should be used instead.
    # RubyGems redefines Kernel#warn so we need to use a subprocess and disable RubyGems here
    code = <<-RUBY
    module Warning
      def warn(*args, **kwargs)
        super
      end
    end
    warn "avoid infinite recursion"
    RUBY
    out = ruby_exe(code, args: "2>&1", options: "--disable-gems")
    out.should == "avoid infinite recursion\n"
    $?.should.success?
  end
end
