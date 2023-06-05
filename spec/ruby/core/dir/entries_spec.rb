# encoding: utf-8

require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Dir.entries" do
  before :all do
    DirSpecs.create_mock_dirs
  end

  before :each do
    @internal = Encoding.default_internal
  end

  after :all do
    DirSpecs.delete_mock_dirs
  end

  after :each do
    Encoding.default_internal = @internal
  end

  it "returns an Array of filenames in an existing directory including dotfiles" do
    a = Dir.entries(DirSpecs.mock_dir).sort

    a.should == DirSpecs.expected_paths

    a = Dir.entries("#{DirSpecs.mock_dir}/deeply/nested").sort
    a.should == %w|. .. .dotfile.ext directory|
  end

  it "calls #to_path on non-String arguments" do
    p = mock('path')
    p.should_receive(:to_path).and_return(DirSpecs.mock_dir)
    Dir.entries(p)
  end

  it "accepts an encoding keyword for the encoding of the entries" do
    dirs = Dir.entries("#{DirSpecs.mock_dir}/deeply/nested", encoding: "utf-8").to_a.sort
    dirs.each {|dir| dir.encoding.should == Encoding::UTF_8}
  end

  it "returns entries encoded with the filesystem encoding by default" do
    # This spec depends on the locale not being US-ASCII because if it is, the
    # entries that are not ascii_only? will be BINARY encoded.
    entries = Dir.entries(File.join(DirSpecs.mock_dir, 'special')).sort
    encoding = Encoding.find("filesystem")
    encoding = Encoding::BINARY if encoding == Encoding::US_ASCII
    platform_is_not :windows do
      entries.should include("こんにちは.txt".force_encoding(encoding))
    end
    entries.first.encoding.should equal(Encoding.find("filesystem"))
  end

  it "returns entries encoded with the specified encoding" do
    dir = File.join(DirSpecs.mock_dir, 'special')
    entries = Dir.entries(dir, encoding: "euc-jp").sort
    entries.first.encoding.should equal(Encoding::EUC_JP)
  end

  it "returns entries transcoded to the default internal encoding" do
    Encoding.default_internal = Encoding::EUC_KR
    entries = Dir.entries(File.join(DirSpecs.mock_dir, 'special')).sort
    entries.first.encoding.should equal(Encoding::EUC_KR)
  end

  it "raises a SystemCallError if called with a nonexistent directory" do
    -> { Dir.entries DirSpecs.nonexistent }.should raise_error(SystemCallError)
  end
end
