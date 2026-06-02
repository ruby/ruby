require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#fail" do
  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:fail)
  end

  it "raises a RuntimeError" do
    -> { fail }.should.raise(RuntimeError)
  end

  it "accepts an Object with an exception method returning an Exception" do
    obj = Object.new
    def obj.exception(msg)
      StandardError.new msg
    end
    -> { fail obj, "..." }.should.raise(StandardError, "...")
  end

  it "instantiates the specified exception class" do
    error_class = Class.new(RuntimeError)
    -> { fail error_class }.should.raise(error_class)
  end

  it "uses the specified message" do
    -> {
      begin
        fail "the duck is not irish."
      rescue => e
        e.message.should == "the duck is not irish."
        raise
      else
        raise Exception
      end
    }.should.raise(RuntimeError)
  end
end

describe "Kernel.fail" do
  it "needs to be reviewed for spec completeness"
end
