require_relative '../../spec_helper'

ruby_version_is "2.5" do
  describe "Integer.sqrt" do
    it "returns an integer" do
      Integer.sqrt(10).should be_kind_of(Integer)
    end

    it "returns the integer square root of the argument" do
      Integer.sqrt(0).should == 0
      Integer.sqrt(1).should == 1
      Integer.sqrt(24).should == 4
      Integer.sqrt(25).should == 5
      Integer.sqrt(10**400).should == 10**200
    end

    it "raises a Math::DomainError if the argument is negative" do
      lambda { Integer.sqrt(-4) }.should raise_error(Math::DomainError)
    end

    it "accepts any argument that can be coerced to Integer" do
      Integer.sqrt(10.0).should == 3
    end

    it "converts the argument with #to_int" do
      Integer.sqrt(mock_int(10)).should == 3
    end

    it "raises a TypeError if the argument cannot be coerced to Integer" do
      lambda { Integer.sqrt("test") }.should raise_error(TypeError)
    end
  end
end
