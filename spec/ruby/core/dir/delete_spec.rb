require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Dir.delete" do
  before :all do
    DirSpecs.create_mock_dirs
  end

  after :all do
    DirSpecs.delete_mock_dirs
  end

  before :each do
    DirSpecs.rmdir_dirs true
  end

  after :each do
    DirSpecs.rmdir_dirs false
  end

  it "removes empty directories" do
    Dir.delete(DirSpecs.mock_rmdir("empty")).should == 0
  end

  it "calls #to_path on non-String arguments" do
    p = mock('path')
    p.should_receive(:to_path).and_return(DirSpecs.mock_rmdir("empty"))
    Dir.delete(p)
  end

  it "raises an Errno::ENOTEMPTY when trying to remove a nonempty directory" do
    -> do
      Dir.delete DirSpecs.mock_rmdir("nonempty")
    end.should.raise(Errno::ENOTEMPTY)
  end

  it "raises an Errno::ENOENT when trying to remove a non-existing directory" do
    -> do
      Dir.delete DirSpecs.nonexistent
    end.should.raise(Errno::ENOENT)
  end

  it "raises an Errno::ENOTDIR when trying to remove a non-directory" do
    file = DirSpecs.mock_rmdir("nonempty/regular")
    touch(file)
    -> do
      Dir.delete file
    end.should.raise(Errno::ENOTDIR)
  end

  # this won't work on Windows, since chmod(0000) does not remove all permissions
  platform_is_not :windows do
    as_user do
      it "raises an Errno::EACCES if lacking adequate permissions to remove the directory" do
        parent = DirSpecs.mock_rmdir("noperm")
        child = DirSpecs.mock_rmdir("noperm", "child")
        File.chmod(0000, parent)
        -> do
          Dir.delete child
        end.should.raise(Errno::EACCES)
      end
    end
  end

  platform_is :darwin do
    it "accepts a path in a non-UTF-8, ASCII-compatible encoding containing non-ASCII characters" do
      dir = tmp("dir_delete_\u{3042}")
      non_utf8_dir = dir.encode(Encoding::Windows_31J)

      begin
        mkdir_p(dir)
        Dir.delete(non_utf8_dir).should == 0
        File.directory?(dir).should == false
      ensure
        rm_r dir
      end
    end
  end
end
