require_relative '../../spec_helper'
require_relative 'shared/equal_value'

describe "Range#==" do
  it_behaves_like :range_eql, :==

  it "returns true if the endpoints are ==" do
    (0..1).should == (0..1.0)
  end

  it "returns true if the endpoints are == for endless ranges" do
    eval("(1.0..)").should == eval("(1.0..)")
  end

  ruby_version_is "2.7" do
    it "returns true if the endpoints are == for beginless ranges" do
      eval("(...10)").should == eval("(...10)")
    end
  end
end
