require_relative '../../spec_helper'
require 'pathname'

describe "Pathname#relative?" do

  it "returns false for the root directory" do
    Pathname.new('/').should_not.relative?
  end

  it "returns false for a dir starting with a slash" do
    Pathname.new('/usr/local/bin').should_not.relative?
  end

  it "returns true for a dir not starting with a slash" do
    Pathname.new('fish').should.relative?
  end

  it "returns true for a dir not starting with a slash" do
    Pathname.new('fish/dog/cow').should.relative?
  end

end
