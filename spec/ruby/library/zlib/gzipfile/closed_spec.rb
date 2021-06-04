require_relative '../../../spec_helper'
require 'stringio'
require 'zlib'

describe "Zlib::GzipFile#closed?" do
  it "returns the closed status" do
    io = StringIO.new
    Zlib::GzipWriter.wrap io do |gzio|
      gzio.should_not.closed?

      gzio.close

      gzio.should.closed?
    end
  end
end
