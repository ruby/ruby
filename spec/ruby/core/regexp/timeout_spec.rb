require_relative '../../spec_helper'

describe "Regexp.timeout" do
  after :each do
    Regexp.timeout = nil
  end

  it "returns global timeout" do
    Regexp.timeout = 3
    Regexp.timeout.should == 3
  end

  it "raises Regexp::TimeoutError after global timeout elapsed" do
    Regexp.timeout = 0.001
    Regexp.timeout.should == 0.001

    -> {
      # A typical ReDoS case
      /^(a*)*$/ =~ "a" * 1000000 + "x"
    }.should raise_error(Regexp::TimeoutError, "regexp match timeout")
  end

  it "raises Regexp::TimeoutError after timeout keyword value elapsed" do
    Regexp.timeout = 3 # This should be ignored
    Regexp.timeout.should == 3

    re = Regexp.new("^a*b?a*$", timeout: 0.001)

    -> {
      re =~ "a" * 1000000 + "x"
    }.should raise_error(Regexp::TimeoutError, "regexp match timeout")
  end
end
