require_relative '../../spec_helper'

describe "SyntaxError#path" do
  it "returns the file path provided to eval" do
    filename = "speccing.rb"

    -> {
      eval("if true", TOPLEVEL_BINDING, filename)
    }.should raise_error(SyntaxError) { |e|
      e.path.should == filename
    }
  end

  it "returns the file path that raised an exception" do
    expected_path = fixture(__FILE__, "syntax_error.rb")

    -> {
      require_relative "fixtures/syntax_error"
    }.should raise_error(SyntaxError) { |e| e.path.should == expected_path }
  end

  it "returns nil when constructed directly" do
    SyntaxError.new.path.should == nil
  end
end
