require_relative '../spec_helper'

require 'socket'
require 'tempfile'

platform_is_not :windows do
  describe "CVE-2018-8779 is resisted by" do
    before :each do
      tmpfile = Tempfile.new("s")
      @path = tmpfile.path
      tmpfile.close(true)
    end

    after :each do
      File.unlink @path if @path && File.socket?(@path)
    end

    it "UNIXServer.open by raising an exception when there is a NUL byte" do
      -> {
        UNIXServer.open(@path+"\0")
      }.should raise_error(ArgumentError, /(path name|string) contains null byte/)
    end

    it "UNIXSocket.open by raising an exception when there is a NUL byte" do
      -> {
        UNIXSocket.open(@path+"\0")
      }.should raise_error(ArgumentError, /(path name|string) contains null byte/)
    end
  end
end
