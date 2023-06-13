require_relative '../../spec_helper'
require_relative 'fixtures/common'

ruby_version_is '3.3' do
  guard -> { Dir.respond_to? :fchdir } do
    describe "Dir.fchdir" do
      before :all do
        DirSpecs.create_mock_dirs
      end

      after :all do
        DirSpecs.delete_mock_dirs
      end

      before :each do
        @dirs = [Dir.new('.')]
        @original = @dirs.first.fileno
      end

      after :each do
        Dir.fchdir(@original)
        @dirs.each(&:close)
      end

      it "changes to the specified directory" do
        dir = Dir.new(DirSpecs.mock_dir)
        @dirs << dir
        Dir.fchdir dir.fileno
        Dir.pwd.should == DirSpecs.mock_dir
      end

      it "returns 0 when successfully changing directory" do
        Dir.fchdir(@original).should == 0
      end

      it "returns the value of the block when a block is given" do
        Dir.fchdir(@original) { :block_value }.should == :block_value
      end

      it "changes to the specified directory for the duration of the block" do
        pwd = Dir.pwd
        dir = Dir.new(DirSpecs.mock_dir)
        @dirs << dir
        Dir.fchdir(dir.fileno) { Dir.pwd }.should == DirSpecs.mock_dir
        Dir.pwd.should == pwd
      end

      it "raises a SystemCallError if the file descriptor given is not valid" do
        -> { Dir.fchdir(-1) }.should raise_error(SystemCallError)
        -> { Dir.fchdir(-1) { } }.should raise_error(SystemCallError)
      end

      it "raises a SystemCallError if the file descriptor given is not for a directory" do
        -> { Dir.fchdir $stdout.fileno }.should raise_error(SystemCallError)
        -> { Dir.fchdir($stdout.fileno) { } }.should raise_error(SystemCallError)
      end
    end
  end

  guard_not -> { Dir.respond_to? :fchdir } do
    describe "Dir.fchdir" do
      it "raises NotImplementedError" do
        -> { Dir.fchdir 1 }.should raise_error(NotImplementedError)
        -> { Dir.fchdir(1) { } }.should raise_error(NotImplementedError)
      end
    end
  end
end
