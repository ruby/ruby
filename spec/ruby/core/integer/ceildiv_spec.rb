require_relative '../../spec_helper'

describe "Integer#ceildiv" do
  ruby_version_is '3.2' do
    it "returns a quotient of division which is rounded up to the nearest integer" do
      0.ceildiv(3).should eql(0)
      1.ceildiv(3).should eql(1)
      3.ceildiv(3).should eql(1)
      4.ceildiv(3).should eql(2)

      4.ceildiv(-3).should eql(-1)
      -4.ceildiv(3).should eql(-1)
      -4.ceildiv(-3).should eql(2)

      3.ceildiv(1.2).should eql(3)
      3.ceildiv(6/5r).should eql(3)

      (10**100-11).ceildiv(10**99-1).should eql(10)
      (10**100-9).ceildiv(10**99-1).should eql(11)
    end
  end
end
