require_relative '../../../spec_helper'
require "tmpdir"

describe "Dir.tmpdir" do
  it "returns the path to a writable and readable directory" do
    dir = Dir.tmpdir
    File.directory?(dir).should be_true
    File.writable?(dir).should be_true
  end
end
