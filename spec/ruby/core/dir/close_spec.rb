require_relative '../../spec_helper'
require_relative 'fixtures/common'
describe "Dir#close" do
  before :all do
    DirSpecs.create_mock_dirs
  end

  after :all do
    DirSpecs.delete_mock_dirs
  end

  it "does not raise an IOError even if the Dir instance is closed" do
    dir = Dir.open DirSpecs.mock_dir
    dir.close.should == nil
    dir.close.should == nil

    guard -> { dir.respond_to? :fileno } do
      -> { dir.fileno }.should raise_error(IOError, /closed directory/)
    end
  end

  it "returns nil" do
    dir = Dir.open DirSpecs.mock_dir
    dir.close.should == nil
  end

  ruby_version_is '3.3'...'3.4' do
    guard -> { Dir.respond_to? :for_fd } do
      it "does not raise an error even if the file descriptor is closed with another Dir instance" do
        dir = Dir.open DirSpecs.mock_dir
        dir_new = Dir.for_fd(dir.fileno)

        dir.close
        dir_new.close

        -> { dir.fileno }.should raise_error(IOError, /closed directory/)
        -> { dir_new.fileno }.should raise_error(IOError, /closed directory/)
      end
    end
  end

  ruby_version_is '3.4' do
    guard -> { Dir.respond_to? :for_fd } do
      it "raises an error if the file descriptor is closed with another Dir instance" do
        dir = Dir.open DirSpecs.mock_dir
        dir_new = Dir.for_fd(dir.fileno)
        dir.close

        -> { dir_new.close }.should raise_error(Errno::EBADF, 'Bad file descriptor - closedir')
      end
    end
  end
end
