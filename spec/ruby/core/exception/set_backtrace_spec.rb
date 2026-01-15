require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative 'shared/set_backtrace'

describe "Exception#set_backtrace" do
  it "allows the user to set the backtrace from a rescued exception" do
    bt  = ExceptionSpecs::Backtrace.backtrace
    err = RuntimeError.new
    err.backtrace.should == nil
    err.backtrace_locations.should == nil

    err.set_backtrace bt

    err.backtrace.should == bt
    err.backtrace_locations.should == nil
  end

  it_behaves_like :exception_set_backtrace, -> backtrace {
    err = RuntimeError.new
    err.set_backtrace(backtrace)
    err
  }
end
