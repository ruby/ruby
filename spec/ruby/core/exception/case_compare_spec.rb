require_relative '../../spec_helper'

describe "SystemCallError.===" do
  before :all do
    @example_errno_class = Errno::EINVAL
    @example_errno = @example_errno_class::Errno
  end

  it "returns true for an instance of the same class" do
    Errno::EINVAL.should === Errno::EINVAL.new
  end

  it "returns true if errnos same" do
    e = SystemCallError.new('foo', @example_errno)
    @example_errno_class.===(e).should == true
  end

  it "returns false if errnos different" do
    e = SystemCallError.new('foo', @example_errno + 1)
    @example_errno_class.===(e).should == false
  end

  it "returns false if arg is not kind of SystemCallError" do
    e = Object.new
    @example_errno_class.===(e).should == false
  end

  it "returns true if receiver is generic and arg is kind of SystemCallError" do
    e = SystemCallError.new('foo', @example_errno)
    SystemCallError.===(e).should == true
  end

  it "returns false if receiver is generic and arg is not kind of SystemCallError" do
    e = Object.new
    SystemCallError.===(e).should == false
  end
end
