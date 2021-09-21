require_relative '../../spec_helper'

require 'securerandom'

describe "SecureRandom.random_string" do
  it "generates a random string of length specified by the second argument" do
    (1..64).each do |idx|
      string = SecureRandom.random_string('abc'.chars, idx)
      string.should be_kind_of(String)
      string.length.should == idx
    end

    string = SecureRandom.random_string('abc'.chars, 5.5)
    string.should be_kind_of(String)
    string.length.should eql(5)
  end

  it "returns an empty string when second argument is 0" do
    SecureRandom.random_string('abc'.chars, 0).should == ""
  end

  it "returns strings that only containg the specified characters" do
    SecureRandom.random_string('abc'.chars, 10).should match(/^[abc]{10}$/)
    SecureRandom.random_string([*'A'..'Z'], 10).should match(/^[A-Z]{10}$/)
    SecureRandom.random_string([*'a'..'z', *'0'..'9'], 10).should match(/^[a-z0-9]{10}$/)
  end

  it "generates different strings with subsequent invocations" do
    values = []
    256.times do
      string = SecureRandom.random_string(*'A'..'Z', 16)
      # make sure the random values are not repeating
      values.include?(string).should == false
      values << string
    end
  end
end
