require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative 'shared/new'

describe "Exception.exception" do
  it_behaves_like :exception_new, :exception
end

describe "Exception#exception" do
  it "returns self when passed no argument" do
    e = RuntimeError.new
    e.should == e.exception
  end

  it "returns self when passed self as an argument" do
    e = RuntimeError.new
    e.should == e.exception(e)
  end

  it "returns an exception of the same class as self with the message given as argument" do
    e = RuntimeError.new
    e2 = e.exception("message")
    e2.should be_an_instance_of(RuntimeError)
    e2.message.should == "message"
  end

  it "when raised will be rescued as the new exception" do
    begin
      begin
        raised_first = StandardError.new('first')
        raise raised_first
      rescue => caught_first
        raised_second = raised_first.exception('second')
        raise raised_second
      end
    rescue => caught_second
    end

    raised_first.should == caught_first
    raised_second.should == caught_second
  end

  it "captures an exception into $!" do
    exception = begin
      raise
    rescue RuntimeError
      $!
    end

    exception.class.should == RuntimeError
    exception.message.should == ""
    exception.backtrace.first.should =~ /exception_spec/
  end

  class CustomArgumentError < StandardError
    attr_reader :val
    def initialize(val)
      @val = val
    end
  end

  it "returns an exception of the same class as self with the message given as argument, but without reinitializing" do
    e = CustomArgumentError.new(:boom)
    e2 = e.exception("message")
    e2.should be_an_instance_of(CustomArgumentError)
    e2.val.should == :boom
    e2.message.should == "message"
  end
end
