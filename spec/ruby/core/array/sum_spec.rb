require_relative '../../spec_helper'

ruby_version_is '2.4' do
  describe "Array#sum" do
    it "returns the sum of elements" do
      [1, 2, 3].sum.should == 6
    end

    it "applies a block to each element before adding if it's given" do
      [1, 2, 3].sum { |i| i * 10 }.should == 60
    end

    it "returns init value if array is empty" do
      [].sum(-1).should == -1
    end

    it "returns 0 if array is empty and init is omitted" do
      [].sum.should == 0
    end

    it "adds init value to the sum of elemens" do
      [1, 2, 3].sum(10).should == 16
    end

    it "can be used for non-numeric objects by providing init value" do
      ["a", "b", "c"].sum("").should == "abc"
    end

    it 'raises TypeError if any element are not numeric' do
      lambda { ["a"].sum }.should raise_error(TypeError)
    end

    it 'raises TypeError if any element cannot be added to init value' do
      lambda { [1].sum([]) }.should raise_error(TypeError)
    end

    it "calls + to sum the elements" do
      a = mock("a")
      b = mock("b")
      a.should_receive(:+).with(b).and_return(42)
      [b].sum(a).should == 42
    end
  end
end
