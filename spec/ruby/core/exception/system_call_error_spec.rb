require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "SystemCallError" do
  before :each do
    ScratchPad.clear
  end

  it "can be subclassed" do
    ExceptionSpecs::SCESub = Class.new(SystemCallError) do
      def initialize
        ScratchPad.record :initialize
      end
    end

    exc = ExceptionSpecs::SCESub.new
    ScratchPad.recorded.should equal(:initialize)
    exc.should be_an_instance_of(ExceptionSpecs::SCESub)
  end
end

describe "SystemCallError.new" do
  before :all do
    @example_errno = Errno::EINVAL::Errno
    @example_errno_class = Errno::EINVAL
    @last_known_errno = Errno.constants.size - 1
    @unknown_errno = Errno.constants.size
  end

  it "requires at least one argument" do
    -> { SystemCallError.new }.should raise_error(ArgumentError)
  end

  it "accepts single Integer argument as errno" do
    SystemCallError.new(-2**24).errno.should == -2**24
    SystemCallError.new(-1).errno.should == -1
    SystemCallError.new(0).errno.should == 0
    SystemCallError.new(@last_known_errno).errno.should == @last_known_errno
    SystemCallError.new(@unknown_errno).errno.should == @unknown_errno
    SystemCallError.new(2**24).errno.should == 2**24
  end

  it "constructs a SystemCallError for an unknown error number" do
    SystemCallError.new(-2**24).should be_an_instance_of(SystemCallError)
    SystemCallError.new(-1).should be_an_instance_of(SystemCallError)
    SystemCallError.new(@unknown_errno).should be_an_instance_of(SystemCallError)
    SystemCallError.new(2**24).should be_an_instance_of(SystemCallError)
  end

  it "constructs the appropriate Errno class" do
    e = SystemCallError.new(@example_errno)
    e.should be_kind_of(SystemCallError)
    e.should be_an_instance_of(@example_errno_class)
  end

  it "accepts an optional custom message preceding the errno" do
    exc = SystemCallError.new("custom message", @example_errno)
    exc.should be_an_instance_of(@example_errno_class)
    exc.errno.should == @example_errno
    exc.message.should == 'Invalid argument - custom message'
  end

  it "accepts an optional third argument specifying the location" do
    exc = SystemCallError.new("custom message", @example_errno, "location")
    exc.should be_an_instance_of(@example_errno_class)
    exc.errno.should == @example_errno
    exc.message.should == 'Invalid argument @ location - custom message'
  end

  it "coerces location if it is not a String" do
    e = SystemCallError.new('foo', 1, :not_a_string)
    e.message.should =~ /@ not_a_string - foo/
  end

  it "returns an arity of -1 for the initialize method" do
    SystemCallError.instance_method(:initialize).arity.should == -1
  end

  it "converts to Integer if errno is a Float" do
    SystemCallError.new('foo', 2.0).should == SystemCallError.new('foo', 2)
    SystemCallError.new('foo', 2.9).should == SystemCallError.new('foo', 2)
  end

  it "converts to Integer if errno is a Complex convertible to Integer" do
    SystemCallError.new('foo', Complex(2.9, 0)).should == SystemCallError.new('foo', 2)
  end

  it "raises TypeError if message is not a String" do
    -> { SystemCallError.new(:foo, 1) }.should raise_error(TypeError, /no implicit conversion of Symbol into String/)
  end

  it "raises TypeError if errno is not an Integer" do
    -> { SystemCallError.new('foo', 'bar') }.should raise_error(TypeError, /no implicit conversion of String into Integer/)
  end

  it "raises RangeError if errno is a Complex not convertible to Integer" do
    -> { SystemCallError.new('foo', Complex(2.9, 1)) }.should raise_error(RangeError, /can't convert/)
  end
end

describe "SystemCallError#errno" do
  it "returns nil when no errno given" do
    SystemCallError.new("message").errno.should == nil
  end

  it "returns the errno given as optional argument to new" do
    SystemCallError.new("message", -2**20).errno.should == -2**20
    SystemCallError.new("message", -1).errno.should == -1
    SystemCallError.new("message", 0).errno.should == 0
    SystemCallError.new("message", 1).errno.should == 1
    SystemCallError.new("message", 42).errno.should == 42
    SystemCallError.new("message", 2**20).errno.should == 2**20
  end
end

describe "SystemCallError#message" do
  it "returns the default message when no message is given" do
    platform_is :aix do
      SystemCallError.new(2**28).message.should =~ /Error .*occurred/i
    end
    platform_is_not :aix do
      SystemCallError.new(2**28).message.should =~ /Unknown error/i
    end
  end

  it "returns the message given as an argument to new" do
    SystemCallError.new("message", 1).message.should =~ /message/
    SystemCallError.new("XXX").message.should =~ /XXX/
  end
end

describe "SystemCallError#dup" do
  it "copies the errno" do
    dup_sce = SystemCallError.new("message", 42).dup
    dup_sce.errno.should == 42
  end
end

describe "SystemCallError#backtrace" do
  it "is nil if not raised" do
    SystemCallError.new("message", 42).backtrace.should == nil
  end
end
