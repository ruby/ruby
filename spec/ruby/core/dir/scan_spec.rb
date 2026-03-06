# encoding: utf-8

require_relative '../../spec_helper'
require_relative 'fixtures/common'
require_relative '../file/fixtures/file_types'

ruby_version_is "4.1" do
  describe "Dir.scan" do
    before :all do
      FileSpecs.configure_types
    end

    before :all do
      DirSpecs.create_mock_dirs
    end

    after :all do
      DirSpecs.delete_mock_dirs
    end

    before :each do
      @internal = Encoding.default_internal
    end

    after :each do
      Encoding.default_internal = @internal
    end

    it "returns an Array of filename and type pairs in an existing directory including dotfiles" do
      a = Dir.scan(DirSpecs.mock_dir).sort

      a.should == DirSpecs.expected_paths_with_type - [[".", :directory], ["..", :directory]]

      a = Dir.scan("#{DirSpecs.mock_dir}/deeply/nested").sort
      a.should == [[".dotfile.ext", :file], ["directory", :directory]]
    end

    it "yields filename and type in an existing directory including dotfiles" do
      a = []
      Dir.scan(DirSpecs.mock_dir) do |n, t|
        a << [n, t]
      end
      a.sort!
      a.should == DirSpecs.expected_paths_with_type - [[".", :directory], ["..", :directory]]

      a = []
      Dir.scan("#{DirSpecs.mock_dir}/deeply/nested") do |n, t|
        a << [n, t]
      end
      a.sort!
      a.should == [[".dotfile.ext", :file], ["directory", :directory]]
    end

    it "calls #to_path on non-String arguments" do
      p = mock('path')
      p.should_receive(:to_path).and_return(DirSpecs.mock_dir)
      Dir.scan(p)
    end

    it "accepts an options Hash" do
      a = Dir.scan("#{DirSpecs.mock_dir}/deeply/nested", encoding: "utf-8").sort
      a.should == [[".dotfile.ext", :file], ["directory", :directory]]
    end

    it "returns children names encoded with the filesystem encoding by default" do
      # This spec depends on the locale not being US-ASCII because if it is, the
      # children that are not ascii_only? will be BINARY encoded.
      children = Dir.scan(File.join(DirSpecs.mock_dir, 'special')).sort
      encoding = Encoding.find("filesystem")
      encoding = Encoding::BINARY if encoding == Encoding::US_ASCII
      platform_is_not :windows do
        children.should include(["こんにちは.txt".dup.force_encoding(encoding), :file])
      end
      children.first.first.encoding.should equal(Encoding.find("filesystem"))
    end

    it "returns children names encoded with the specified encoding" do
      dir = File.join(DirSpecs.mock_dir, 'special')
      children = Dir.scan(dir, encoding: "euc-jp").sort
      children.first.first.encoding.should equal(Encoding::EUC_JP)
    end

    it "returns children names transcoded to the default internal encoding" do
      Encoding.default_internal = Encoding::EUC_KR
      children = Dir.scan(File.join(DirSpecs.mock_dir, 'special')).sort
      children.first.first.encoding.should equal(Encoding::EUC_KR)
    end

    it "raises a SystemCallError if called with a nonexistent directory" do
      -> { Dir.scan DirSpecs.nonexistent }.should raise_error(SystemCallError)
    end

    it "handles symlink" do
      FileSpecs.symlink do |path|
        Dir.scan(File.dirname(path)).map(&:last).should include(:link)
      end
    end

    platform_is_not :windows do
      it "handles socket" do
        FileSpecs.socket do |path|
          Dir.scan(File.dirname(path)).map(&:last).should include(:socket)
        end
      end

      it "handles FIFO" do
        FileSpecs.fifo do |path|
          Dir.scan(File.dirname(path)).map(&:last).should include(:fifo)
        end
      end

      it "handles character devices" do
        FileSpecs.character_device do |path|
          Dir.scan(File.dirname(path)).map(&:last).should include(:characterSpecial)
        end
      end
    end

    platform_is_not :freebsd, :windows do
      with_block_device do
        it "handles block devices" do
          FileSpecs.block_device do |path|
            Dir.scan(File.dirname(path)).map(&:last).should include(:blockSpecial)
          end
        end
      end
    end
  end

  describe "Dir#scan" do
    before :all do
      DirSpecs.create_mock_dirs
    end

    after :all do
      DirSpecs.delete_mock_dirs
    end

    before :each do
      @internal = Encoding.default_internal
    end

    after :each do
      Encoding.default_internal = @internal
      @dir.close if @dir
    end

    it "returns an Array of filenames in an existing directory including dotfiles" do
      @dir = Dir.new(DirSpecs.mock_dir)
      a = @dir.scan.sort
      @dir.close

      a.should == DirSpecs.expected_paths_with_type - [[".", :directory], ["..", :directory]]

      @dir = Dir.new("#{DirSpecs.mock_dir}/deeply/nested")
      a = @dir.scan.sort
      a.should == [[".dotfile.ext", :file], ["directory", :directory]]
    end

    it "yields filename and type in an existing directory including dotfiles" do
      @dir = Dir.new(DirSpecs.mock_dir)
      a = []
      @dir.scan do |n, t|
        a << [n, t]
      end
      a.sort!
      a.should == DirSpecs.expected_paths_with_type - [[".", :directory], ["..", :directory]]

      @dir = Dir.new("#{DirSpecs.mock_dir}/deeply/nested")
      a = []
      @dir.scan do |n, t|
        a << [n, t]
      end
      a.sort!
      a.should == [[".dotfile.ext", :file], ["directory", :directory]]
    end

    it "accepts an encoding keyword for the encoding of the entries" do
      @dir = Dir.new("#{DirSpecs.mock_dir}/deeply/nested", encoding: "utf-8")
      dirs = @dir.to_a.sort
      dirs.each { |d| d.encoding.should == Encoding::UTF_8 }
    end

    it "returns children names encoded with the filesystem encoding by default" do
      # This spec depends on the locale not being US-ASCII because if it is, the
      # children that are not ascii_only? will be BINARY encoded.
      @dir = Dir.new(File.join(DirSpecs.mock_dir, 'special'))
      children = @dir.scan.sort
      encoding = Encoding.find("filesystem")
      encoding = Encoding::BINARY if encoding == Encoding::US_ASCII
      platform_is_not :windows do
        children.should include(["こんにちは.txt".dup.force_encoding(encoding), :file])
      end
      children.first.first.encoding.should equal(Encoding.find("filesystem"))
    end

    it "returns children names encoded with the specified encoding" do
      path = File.join(DirSpecs.mock_dir, 'special')
      @dir = Dir.new(path, encoding: "euc-jp")
      children = @dir.children.sort
      children.first.encoding.should equal(Encoding::EUC_JP)
    end

    it "returns children names transcoded to the default internal encoding" do
      Encoding.default_internal = Encoding::EUC_KR
      @dir = Dir.new(File.join(DirSpecs.mock_dir, 'special'))
      children = @dir.scan.sort
      children.first.first.encoding.should equal(Encoding::EUC_KR)
    end

    it "returns the same result when called repeatedly" do
      @dir = Dir.open DirSpecs.mock_dir

      a = []
      @dir.each {|dir| a << dir}

      b = []
      @dir.each {|dir| b << dir}

      a.sort.should == b.sort
      a.sort.should == DirSpecs.expected_paths
    end
  end
end
