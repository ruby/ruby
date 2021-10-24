require_relative '../../spec_helper'

describe "ENV.empty?" do

  it "returns true if the Environment is empty" do
    if ENV.keys.size > 0
      ENV.should_not.empty?
    end
    orig = ENV.to_hash
    begin
      ENV.clear
      ENV.should.empty?
    ensure
      ENV.replace orig
    end
  end

  it "returns false if not empty" do
    if ENV.keys.size > 0
      ENV.should_not.empty?
    end
  end
end
