require_relative '../../spec_helper'
require_relative 'shared/update_time'

platform_is_not :windows do
  describe "File.lutime" do
    it_behaves_like :update_time, :lutime
  end

  describe "File.lutime" do
    before :each do
      @atime = Time.utc(2000)
      @mtime = Time.utc(2001)
      @file = tmp("specs_lutime_file")
      @symlink = tmp("specs_lutime_symlink")
      touch @file
      File.symlink(@file, @symlink)
    end

    after :each do
      rm_r @file, @symlink
    end

    it "sets the access and modification time for a regular file" do
      File.lutime(@atime, @mtime, @file)
      stat = File.stat(@file)
      stat.atime.should == @atime
      stat.mtime.should === @mtime
    end

    it "sets the access and modification time for a symlink" do
      original = File.stat(@file)

      File.lutime(@atime, @mtime, @symlink)
      stat = File.lstat(@symlink)
      stat.atime.should == @atime
      stat.mtime.should === @mtime

      file = File.stat(@file)
      file.atime.should == original.atime
      file.mtime.should == original.mtime
    end
  end
end
