require_relative '../../spec_helper'
require 'pathname'

describe "Pathname#absolute?" do

  it "returns true for the root directory" do
    Pathname.new('/').should.absolute?
  end

  it "returns true for a dir starting with a slash" do
    Pathname.new('/usr/local/bin').should.absolute?
  end

  it "returns false for a dir not starting with a slash" do
    Pathname.new('fish').should_not.absolute?
  end

  it "returns false for a dir not starting with a slash" do
    Pathname.new('fish/dog/cow').should_not.absolute?
  end

end
