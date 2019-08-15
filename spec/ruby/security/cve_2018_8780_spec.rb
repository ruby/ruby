require_relative '../spec_helper'

describe "CVE-2018-8780 is resisted by" do
  before :all do
    @root = File.realpath(tmp(""))
  end

  it "Dir.glob by raising an exception when there is a NUL byte" do
    -> {
      Dir.glob([[@root, File.join(@root, "*")].join("\0")])
    }.should raise_error(ArgumentError, /(path name|string) contains null byte/)
  end

  it "Dir.entries by raising an exception when there is a NUL byte" do
    -> {
      Dir.entries(@root+"\0")
    }.should raise_error(ArgumentError, /(path name|string) contains null byte/)
  end

  it "Dir.foreach by raising an exception when there is a NUL byte" do
    -> {
      Dir.foreach(@root+"\0").to_a
    }.should raise_error(ArgumentError, /(path name|string) contains null byte/)
  end

  it "Dir.empty? by raising an exception when there is a NUL byte" do
    -> {
      Dir.empty?(@root+"\0")
    }.should raise_error(ArgumentError, /(path name|string) contains null byte/)
  end

  ruby_version_is "2.5" do
    it "Dir.children by raising an exception when there is a NUL byte" do
      -> {
        Dir.children(@root+"\0")
      }.should raise_error(ArgumentError, /(path name|string) contains null byte/)
    end

    it "Dir.each_child by raising an exception when there is a NUL byte" do
      -> {
        Dir.each_child(@root+"\0").to_a
      }.should raise_error(ArgumentError, /(path name|string) contains null byte/)
    end
  end
end
