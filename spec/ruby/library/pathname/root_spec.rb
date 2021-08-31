require_relative '../../spec_helper'
require 'pathname'

describe "Pathname#root?" do

  it "returns true for root directories" do
    Pathname.new('/').should.root?
  end

  it "returns false for empty string" do
    Pathname.new('').should_not.root?
  end

  it "returns false for a top level directory" do
    Pathname.new('/usr').should_not.root?
  end

  it "returns false for a top level with .. appended directory" do
    Pathname.new('/usr/..').should_not.root?
  end

  it "returns false for a directory below top level" do
    Pathname.new('/usr/local/bin/').should_not.root?
  end

end
