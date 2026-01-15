require_relative '../../spec_helper'
require_relative 'fixtures/common'

quarantine! do # leads to "Errno::EBADF: Bad file descriptor - closedir" in DirSpecs.delete_mock_dirs
ruby_version_is '3.3' do
  platform_is_not :windows do
    describe "Dir.for_fd" do
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

      it "returns a new Dir object representing the directory specified by the given integer directory file descriptor" do
        dir = Dir.new(DirSpecs.mock_dir)
        dir_new = Dir.for_fd(dir.fileno)

        dir_new.should.instance_of?(Dir)
        dir_new.children.should == dir.children
        dir_new.fileno.should == dir.fileno
      ensure
        dir.close
      end

      it "returns a new Dir object without associated path" do
        dir = Dir.new(DirSpecs.mock_dir)
        dir_new = Dir.for_fd(dir.fileno)

        dir_new.path.should == nil
      ensure
        dir.close
      end

      it "calls #to_int to convert a value to an Integer" do
        dir = Dir.new(DirSpecs.mock_dir)
        obj = mock("fd")
        obj.should_receive(:to_int).and_return(dir.fileno)

        dir_new = Dir.for_fd(obj)
        dir_new.fileno.should == dir.fileno
      ensure
        dir.close
      end

      it "raises TypeError when value cannot be converted to Integer" do
        -> {
          Dir.for_fd(nil)
        }.should raise_error(TypeError, "no implicit conversion from nil to integer")
      end

      it "raises a SystemCallError if the file descriptor given is not valid" do
        -> { Dir.for_fd(-1) }.should raise_error(SystemCallError, "Bad file descriptor - fdopendir")
      end

      it "raises a SystemCallError if the file descriptor given is not for a directory" do
        -> { Dir.for_fd $stdout.fileno }.should raise_error(SystemCallError, "Not a directory - fdopendir")
      end
    end
  end

  platform_is :windows do
    describe "Dir.for_fd" do
      it "raises NotImplementedError" do
        -> { Dir.for_fd 1 }.should raise_error(NotImplementedError)
      end
    end
  end
end
end
