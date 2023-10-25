require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Errno::EINVAL.new" do
  it "can be called with no arguments" do
    exc = Errno::EINVAL.new
    exc.should be_an_instance_of(Errno::EINVAL)
    exc.errno.should == Errno::EINVAL::Errno
    exc.message.should == "Invalid argument"
  end

  it "accepts an optional custom message" do
    exc = Errno::EINVAL.new('custom message')
    exc.should be_an_instance_of(Errno::EINVAL)
    exc.errno.should == Errno::EINVAL::Errno
    exc.message.should == "Invalid argument - custom message"
  end

  it "accepts an optional custom message and location" do
    exc = Errno::EINVAL.new('custom message', 'location')
    exc.should be_an_instance_of(Errno::EINVAL)
    exc.errno.should == Errno::EINVAL::Errno
    exc.message.should == "Invalid argument @ location - custom message"
  end
end

describe "Errno::EMFILE" do
  it "can be subclassed" do
    ExceptionSpecs::EMFILESub = Class.new(Errno::EMFILE)
    exc = ExceptionSpecs::EMFILESub.new
    exc.should be_an_instance_of(ExceptionSpecs::EMFILESub)
  end
end

describe "Errno::EAGAIN" do
  # From http://jira.codehaus.org/browse/JRUBY-4747
  it "is the same class as Errno::EWOULDBLOCK if they represent the same errno value" do
    if Errno::EAGAIN::Errno == Errno::EWOULDBLOCK::Errno
      Errno::EAGAIN.should == Errno::EWOULDBLOCK
    else
      Errno::EAGAIN.should_not == Errno::EWOULDBLOCK
    end
  end
end

describe "Errno::ENOTSUP" do
  it "is defined" do
    Errno.should have_constant(:ENOTSUP)
  end

  it "is the same class as Errno::EOPNOTSUPP if they represent the same errno value" do
    if Errno::ENOTSUP::Errno == Errno::EOPNOTSUPP::Errno
      Errno::ENOTSUP.should == Errno::EOPNOTSUPP
    else
      Errno::ENOTSUP.should_not == Errno::EOPNOTSUPP
    end
  end
end

describe "Errno::ENOENT" do
  it "lets subclasses inherit the default error message" do
    c = Class.new(Errno::ENOENT)
    raise c, "custom message"
  rescue => e
    e.message.should == "No such file or directory - custom message"
  end
end
