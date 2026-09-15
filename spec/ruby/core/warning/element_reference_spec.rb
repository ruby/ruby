require_relative '../../spec_helper'

describe "Warning.[]" do
  it "returns default values for categories :deprecated and :experimental" do
    # If any warning options were set on the Ruby that will be executed, then
    # it's possible this test will fail. In this case we will skip this test.
    skip if ruby_exe.any? { |opt| opt.start_with?("-W") }
    # RUBYOPT can carry -W too, and the defaults are what this example is about.
    no_rubyopt = { "RUBYOPT" => nil }

    ruby_exe('p [Warning[:deprecated], Warning[:experimental]]', env: no_rubyopt).chomp.should == "[false, true]"
    ruby_exe('p [Warning[:deprecated], Warning[:experimental]]', options: "-w", env: no_rubyopt).chomp.should == "[true, true]"
  end

  it "returns default values for :performance category" do
    ruby_exe('p Warning[:performance]').chomp.should == "false"
    ruby_exe('p Warning[:performance]', options: "-w").chomp.should == "false"
  end

  it "raises for unknown category" do
    -> { Warning[:noop] }.should.raise(ArgumentError, /unknown category: noop/)
  end

  it "raises for non-Symbol category" do
    -> { Warning[42] }.should.raise(TypeError)
    -> { Warning[false] }.should.raise(TypeError)
    -> { Warning["noop"] }.should.raise(TypeError)
  end
end
