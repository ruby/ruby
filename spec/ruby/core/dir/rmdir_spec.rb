require_relative '../../spec_helper'

describe "Dir.rmdir" do
  it "is an alias of Dir.delete" do
    Dir.method(:rmdir).should == Dir.method(:delete)
  end

  ruby_version_is "4.1" do
    before :each do
      @dir = tmp("dir_rmdir_parents")
      mkdir_p "#{@dir}/a/b"
    end

    after :each do
      rm_r @dir
    end

    it "removes successive empty parent directories with parents: true" do
      Dir.chdir(@dir) do
        Dir.rmdir("a/b", parents: true).should == 0
        File.should_not.exist?("a")
        File.should.directory?(".")
      end
    end

    it "leaves parent directories with parents: false" do
      Dir.rmdir("#{@dir}/a/b", parents: false).should == 0
      File.should_not.exist?("#{@dir}/a/b")
      File.should.directory?("#{@dir}/a")
    end

    it "raises when the directory itself is not empty with parents: true" do
      -> {Dir.rmdir("#{@dir}/a", parents: true)}.should.raise(Errno::ENOTEMPTY)
      File.should.directory?("#{@dir}/a/b")
    end

    it "raises when a parent directory is not empty" do
      touch "#{@dir}/keep"
      -> {Dir.rmdir("#{@dir}/a/b", parents: true)}.should.raise(Errno::ENOTEMPTY)
      File.should_not.exist?("#{@dir}/a")
      File.should.exist?("#{@dir}/keep")
    end

    it "stops successfully at a nonempty parent with ignore_non_empty: true" do
      touch "#{@dir}/keep"
      Dir.rmdir("#{@dir}/a/b", parents: true, ignore_non_empty: true).should == 0
      File.should_not.exist?("#{@dir}/a")
      File.should.exist?("#{@dir}/keep")
    end

    it "ignores a nonempty target with ignore_non_empty: true" do
      Dir.rmdir("#{@dir}/a", ignore_non_empty: true).should == 0
      File.should.directory?("#{@dir}/a/b")
    end

    it "does not ignore a missing target with ignore_non_empty: true" do
      -> {Dir.rmdir("#{@dir}/missing", ignore_non_empty: true)}.should.raise(Errno::ENOENT)
    end

    it "ignores a nonempty parent with ignore_non_empty: :parents" do
      touch "#{@dir}/keep"
      Dir.rmdir("#{@dir}/a/b", parents: true, ignore_non_empty: :parents).should == 0
      File.should_not.exist?("#{@dir}/a")
      File.should.exist?("#{@dir}/keep")
    end

    it "does not ignore a nonempty target with ignore_non_empty: :parents" do
      -> {Dir.rmdir("#{@dir}/a", parents: true, ignore_non_empty: :parents)}.should.raise(Errno::ENOTEMPTY)
      File.should.directory?("#{@dir}/a/b")
    end

    it "does not remove parents when only ignore_non_empty: :parents is given" do
      Dir.rmdir("#{@dir}/a/b", ignore_non_empty: :parents).should == 0
      File.should_not.exist?("#{@dir}/a/b")
      File.should.directory?("#{@dir}/a")
    end
  end
end
