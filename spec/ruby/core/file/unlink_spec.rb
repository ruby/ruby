require_relative '../../spec_helper'

describe "File.unlink" do
  it "is an alias of File.delete" do
    File.method(:unlink).should == File.method(:delete)
  end
end

ruby_version_is "4.1" do
  describe "File.unlink with recursive: true" do
    before :each do
      @tree = tmp('unlink_recursive')
      mkdir_p "#{@tree}/subdir"
      touch "#{@tree}/subdir/file"
    end

    after :each do
      rm_r @tree
    end

    it "removes a directory and its contents" do
      File.unlink(@tree, recursive: true).should == 1
      File.should_not.exist?(@tree)
    end

    it "returns the number of arguments, regardless of the tree size" do
      file = "#{@tree}/subdir/file"
      File.unlink(file, @tree, recursive: true).should == 2
    end

    it "raises when the given path does not exist" do
      -> { File.unlink("#{@tree}/missing", recursive: true) }.should.raise(Errno::ENOENT)
    end

    platform_is_not :windows do
      it "does not follow symbolic links" do
        File.symlink('subdir', "#{@tree}/link")
        File.unlink("#{@tree}/link", recursive: true).should == 1
        File.should.exist?("#{@tree}/subdir/file")
        File.should_not.symlink?("#{@tree}/link")
      end
    end
  end
end
