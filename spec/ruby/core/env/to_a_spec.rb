require_relative '../../spec_helper'

describe "ENV.to_a" do

  it "returns the ENV as an array" do
    a = ENV.to_a
    a.is_a?(Array).should == true
    a.size.should == ENV.size
    ENV.each_pair { |k, v| a.should include([k, v])}
  end

  it "returns the entries in the locale encoding" do
    ENV.to_a.each do |key, value|
      key.encoding.should == Encoding.find('locale')
      value.encoding.should == Encoding.find('locale')
    end
  end
end
