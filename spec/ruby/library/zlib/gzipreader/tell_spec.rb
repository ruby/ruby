require_relative "../../../spec_helper"
require 'zlib'

describe "Zlib::GzipReader#tell" do
  it "is an alias of Zlib::GzipReader#pos" do
    Zlib::GzipReader.instance_method(:tell).should ==
      Zlib::GzipReader.instance_method(:pos)
  end
end
