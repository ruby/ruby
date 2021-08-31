require_relative '../../spec_helper'

describe "ENV.keys" do

  it "returns an array of the keys" do
    ENV.keys.should == ENV.to_hash.keys
  end

  it "returns the keys in the locale encoding" do
    ENV.keys.each do |key|
      key.encoding.should == Encoding.find('locale')
    end
  end
end
