require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/sprintf'
require_relative 'shared/sprintf_encoding'

describe "Kernel#sprintf" do
  it_behaves_like :kernel_sprintf, -> format, *args {
    r = nil
    -> {
      r = sprintf(format, *args)
    }.should_not complain(verbose: true)
    r
  }

  it_behaves_like :kernel_sprintf_encoding, -> format, *args {
    r = nil
    -> {
      r = sprintf(format, *args)
    }.should_not complain(verbose: true)
    r
  }

  it "calls #to_str to convert the format object to a String" do
    obj = mock('format string')
    obj.should_receive(:to_str).and_return("to_str: %i")
    @method.call(obj, 42).should == "to_str: 42"
  end
end

describe "Kernel.sprintf" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:sprintf)
  end
end
