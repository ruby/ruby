require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#to_s" do
  it "returns a String containing the name of self's class" do
    Object.new.to_s.should =~ /Object/
  end
end
