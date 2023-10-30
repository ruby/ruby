require_relative '../../spec_helper'

describe "Warning.[]" do
  it "returns default values for categories :deprecated and :experimental" do
    ruby_exe('p [Warning[:deprecated], Warning[:experimental]]').chomp.should == "[false, true]"
    ruby_exe('p [Warning[:deprecated], Warning[:experimental]]', options: "-w").chomp.should == "[true, true]"
  end

  ruby_version_is '3.3' do
    it "returns default values for :performance category" do
      ruby_exe('p Warning[:performance]').chomp.should == "false"
      ruby_exe('p Warning[:performance]', options: "-w").chomp.should == "false"
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
