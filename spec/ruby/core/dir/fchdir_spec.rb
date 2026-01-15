require_relative '../../spec_helper'
require_relative 'fixtures/common'

ruby_version_is '3.3' do
  platform_is_not :windows do
    describe "Dir.fchdir" do
      before :all do
        DirSpecs.create_mock_dirs
      end

      after :all do
        DirSpecs.delete_mock_dirs
      end

      before :each do
        @original = Dir.pwd
      end

      after :each do
        Dir.chdir(@original)
      end

      it "changes the current working directory to the directory specified by the integer file descriptor" do
        dir = Dir.new(DirSpecs.mock_dir)
        Dir.fchdir dir.fileno
        Dir.pwd.should == DirSpecs.mock_dir
      ensure
        dir.close
      end

      it "returns 0 when successfully changing directory" do
        dir = Dir.new(DirSpecs.mock_dir)
        Dir.fchdir(dir.fileno).should == 0
      ensure
        dir.close
      end

      it "returns the value of the block when a block is given" do
        dir = Dir.new(DirSpecs.mock_dir)
        Dir.fchdir(dir.fileno) { :block_value }.should == :block_value
      ensure
        dir.close
      end

      it "changes to the specified directory for the duration of the block" do
        dir = Dir.new(DirSpecs.mock_dir)
        Dir.fchdir(dir.fileno) { Dir.pwd }.should == DirSpecs.mock_dir
        Dir.pwd.should == @original
      ensure
        dir.close
      end

      it "raises a SystemCallError if the file descriptor given is not valid" do
        -> { Dir.fchdir(-1) }.should raise_error(SystemCallError, "Bad file descriptor - fchdir")
        -> { Dir.fchdir(-1) { } }.should raise_error(SystemCallError, "Bad file descriptor - fchdir")
      end

      it "raises a SystemCallError if the file descriptor given is not for a directory" do
        -> { Dir.fchdir $stdout.fileno }.should raise_error(SystemCallError, /(Not a directory|Invalid argument) - fchdir/)
        -> { Dir.fchdir($stdout.fileno) { } }.should raise_error(SystemCallError, /(Not a directory|Invalid argument) - fchdir/)
      end
    end
  end

  platform_is :windows do
    describe "Dir.fchdir" do
      it "raises NotImplementedError" do
        -> { Dir.fchdir 1 }.should raise_error(NotImplementedError)
        -> { Dir.fchdir(1) { } }.should raise_error(NotImplementedError)
      end
    end
  end
end
