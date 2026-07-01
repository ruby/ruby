require_relative "../../../spec_helper"
require 'zlib'

describe "Zlib::GzipReader#each_line" do
  it "is an alias of Zlib::GzipReader#each" do
    Zlib::GzipReader.instance_method(:each_line).should ==
      Zlib::GzipReader.instance_method(:each)
  end
end
