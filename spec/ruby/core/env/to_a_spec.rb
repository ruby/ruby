require_relative 'spec_helper'

describe "ENV.to_a" do

  it "returns the ENV as an array" do
    a = ENV.to_a
    a.is_a?(Array).should == true
    a.size.should == ENV.size
    a.each { |k,v| ENV[k].should == v }

    a.first.should.is_a?(Array)
    a.first.size.should == 2
  end

  it "returns the entries in the locale encoding" do
    ENV.to_a.each do |key, value|
      key.should.be_locale_env
      value.should.be_locale_env
    end
  end
end
