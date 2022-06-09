require_relative '../../spec_helper'

describe "Warning.[]" do
  ruby_version_is '2.7.2' do
    it "returns default values for categories :deprecated and :experimental" do
      ruby_exe('p Warning[:deprecated]').chomp.should == "false"
      ruby_exe('p Warning[:experimental]').chomp.should == "true"
    end
  end

  it "raises for unknown category" do
    -> { Warning[:noop] }.should raise_error(ArgumentError, /unknown category: noop/)
  end

  it "raises for non-Symbol category" do
    -> { Warning[42] }.should raise_error(TypeError)
    -> { Warning[false] }.should raise_error(TypeError)
    -> { Warning["noop"] }.should raise_error(TypeError)
  end
end
