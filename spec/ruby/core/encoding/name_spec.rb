require_relative "../../spec_helper"

describe "Encoding#name" do
  it "returns a String" do
    Encoding.list.each do |e|
      e.name.should.instance_of?(String)
    end
  end

  it "uniquely identifies an encoding" do
    Encoding.list.each do |e|
      e.should == Encoding.find(e.name)
    end
  end
end
