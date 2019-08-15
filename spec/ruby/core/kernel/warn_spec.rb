require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#warn" do
  before :each do
    @before_verbose = $VERBOSE
    @before_separator = $/
  end

  after :each do
    $VERBOSE = @before_verbose
    $/ = @before_separator
  end

  it "is a private method" do
    Kernel.should have_private_instance_method(:warn)
  end

  it "requires multiple arguments" do
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

  ruby_version_is "2.5" do
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

      it "does not prepend caller information if line number is too big" do
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
  end
end
