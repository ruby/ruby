# encoding: utf-8

require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Dir.children" do
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
    a = Dir.children(DirSpecs.mock_dir).sort

    a.should == DirSpecs.expected_paths - %w[. ..]

    a = Dir.children("#{DirSpecs.mock_dir}/deeply/nested").sort
    a.should == %w|.dotfile.ext directory|
  end

  it "calls #to_path on non-String arguments" do
    p = mock('path')
    p.should_receive(:to_path).and_return(DirSpecs.mock_dir)
    Dir.children(p)
  end

  it "accepts an options Hash" do
    a = Dir.children("#{DirSpecs.mock_dir}/deeply/nested", encoding: "utf-8").sort
    a.should == %w|.dotfile.ext directory|
  end

  it "returns children encoded with the filesystem encoding by default" do
    # This spec depends on the locale not being US-ASCII because if it is, the
    # children that are not ascii_only? will be BINARY encoded.
    children = Dir.children(File.join(DirSpecs.mock_dir, 'special')).sort
    encoding = Encoding.find("filesystem")
    encoding = Encoding::BINARY if encoding == Encoding::US_ASCII
    platform_is_not :windows do
      children.should include("こんにちは.txt".dup.force_encoding(encoding))
    end
    children.first.encoding.should equal(Encoding.find("filesystem"))
  end

  it "returns children encoded with the specified encoding" do
    dir = File.join(DirSpecs.mock_dir, 'special')
    children = Dir.children(dir, encoding: "euc-jp").sort
    children.first.encoding.should equal(Encoding::EUC_JP)
  end

  it "returns children transcoded to the default internal encoding" do
    Encoding.default_internal = Encoding::EUC_KR
    children = Dir.children(File.join(DirSpecs.mock_dir, 'special')).sort
    children.first.encoding.should equal(Encoding::EUC_KR)
  end

  it "raises a SystemCallError if called with a nonexistent directory" do
    -> { Dir.children DirSpecs.nonexistent }.should raise_error(SystemCallError)
  end
end

describe "Dir#children" do
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
    @dir.close if @dir
  end

  it "returns an Array of filenames in an existing directory including dotfiles" do
    @dir = Dir.new(DirSpecs.mock_dir)
    a = @dir.children.sort
    @dir.close

    a.should == DirSpecs.expected_paths - %w[. ..]

    @dir = Dir.new("#{DirSpecs.mock_dir}/deeply/nested")
    a = @dir.children.sort
    a.should == %w|.dotfile.ext directory|
  end

  it "accepts an encoding keyword for the encoding of the entries" do
    @dir = Dir.new("#{DirSpecs.mock_dir}/deeply/nested", encoding: "utf-8")
    dirs = @dir.to_a.sort
    dirs.each { |d| d.encoding.should == Encoding::UTF_8 }
  end

  it "returns children encoded with the filesystem encoding by default" do
    # This spec depends on the locale not being US-ASCII because if it is, the
    # children that are not ascii_only? will be BINARY encoded.
    @dir = Dir.new(File.join(DirSpecs.mock_dir, 'special'))
    children = @dir.children.sort
    encoding = Encoding.find("filesystem")
    encoding = Encoding::BINARY if encoding == Encoding::US_ASCII
    platform_is_not :windows do
      children.should include("こんにちは.txt".dup.force_encoding(encoding))
    end
    children.first.encoding.should equal(Encoding.find("filesystem"))
  end

  it "returns children encoded with the specified encoding" do
    path = File.join(DirSpecs.mock_dir, 'special')
    @dir = Dir.new(path, encoding: "euc-jp")
    children = @dir.children.sort
    children.first.encoding.should equal(Encoding::EUC_JP)
  end

  it "returns children transcoded to the default internal encoding" do
    Encoding.default_internal = Encoding::EUC_KR
    @dir = Dir.new(File.join(DirSpecs.mock_dir, 'special'))
    children = @dir.children.sort
    children.first.encoding.should equal(Encoding::EUC_KR)
  end
end
