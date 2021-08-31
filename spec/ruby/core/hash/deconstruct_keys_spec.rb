require_relative '../../spec_helper'

ruby_version_is "2.7" do
  describe "Hash#deconstruct_keys" do
    it "returns self" do
      hash = {a: 1, b: 2}

      hash.deconstruct_keys([:a, :b]).should equal hash
    end

    it "requires one argument" do
      -> {
        {a: 1}.deconstruct_keys
      }.should raise_error(ArgumentError, /wrong number of arguments \(given 0, expected 1\)/)
    end

    it "ignores argument" do
      hash = {a: 1, b: 2}

      hash.deconstruct_keys([:a]).should == {a: 1, b: 2}
      hash.deconstruct_keys(0   ).should == {a: 1, b: 2}
      hash.deconstruct_keys(''  ).should == {a: 1, b: 2}
    end
  end
end
