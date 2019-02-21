require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Exception#dup" do
  before :each do
    @obj = ExceptionSpecs::InitializeException.new("my exception")
  end

  it "calls #initialize_copy on the new instance" do
    dup = @obj.dup
    ScratchPad.recorded.should_not == @obj.object_id
    ScratchPad.recorded.should == dup.object_id
  end

  it "copies instance variables" do
    dup = @obj.dup
    dup.ivar.should == 1
  end

  it "does not copy singleton methods" do
    def @obj.special() :the_one end
    dup = @obj.dup
    lambda { dup.special }.should raise_error(NameError)
  end

  it "does not copy modules included in the singleton class" do
    class << @obj
      include ExceptionSpecs::ExceptionModule
    end

    dup = @obj.dup
    lambda { dup.repr }.should raise_error(NameError)
  end

  it "does not copy constants defined in the singleton class" do
    class << @obj
      CLONE = :clone
    end

    dup = @obj.dup
    lambda { class << dup; CLONE; end }.should raise_error(NameError)
  end

  it "does copy the message" do
    @obj.dup.message.should == @obj.message
  end

  it "does copy the backtrace" do
    begin
      # Explicitly raise so a backtrace is associated with the exception.
      # It's tempting to call `set_backtrace` instead, but that complicates
      # the test because it might affect other state (e.g., instance variables)
      # on some implementations.
      raise ExceptionSpecs::InitializeException.new("my exception")
    rescue => e
      @obj = e
    end

    @obj.dup.backtrace.should == @obj.backtrace
  end

  it "does copy the cause" do
    begin
      raise StandardError, "the cause"
    rescue StandardError => cause
      begin
        raise RuntimeError, "the consequence"
      rescue RuntimeError => e
        e.cause.should equal(cause)
        e.dup.cause.should equal(cause)
      end
    end
  end
end
