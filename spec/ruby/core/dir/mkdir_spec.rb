require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Dir.mkdir" do
  before :all do
    DirSpecs.create_mock_dirs
  end

  after :all do
    DirSpecs.delete_mock_dirs
  end

  it "creates the named directory with the given permissions" do
    DirSpecs.clear_dirs

    nonexisting = DirSpecs.mock_dir('nonexisting')
    default_perms = DirSpecs.mock_dir('default_perms')
    reduced = DirSpecs.mock_dir('reduced')
    begin
      File.should_not.exist?(nonexisting)
      Dir.mkdir nonexisting
      File.should.exist?(nonexisting)
      platform_is_not :windows do
        Dir.mkdir default_perms
        a = File.stat(default_perms).mode
        Dir.mkdir reduced, (a - 1)
        File.stat(reduced).mode.should_not == a
      end
      platform_is :windows do
        Dir.mkdir default_perms, 0666
        a = File.stat(default_perms).mode
        Dir.mkdir reduced, 0444
        File.stat(reduced).mode.should_not == a
      end

      always_returns_0 = DirSpecs.mock_dir('always_returns_0')
      Dir.mkdir(always_returns_0).should == 0
      platform_is_not(:windows) do
        File.chmod(0777, nonexisting, default_perms, reduced, always_returns_0)
      end
      platform_is_not(:windows) do
        File.chmod(0644, nonexisting, default_perms, reduced, always_returns_0)
      end
    ensure
      DirSpecs.clear_dirs
    end
  end

  it "calls #to_path on non-String arguments" do
    DirSpecs.clear_dirs
    p = mock('path')
    p.should_receive(:to_path).and_return(DirSpecs.mock_dir('nonexisting'))
    Dir.mkdir(p)
    DirSpecs.clear_dirs
  end

  it "raises a SystemCallError if any of the directories in the path before the last does not exist" do
    -> { Dir.mkdir "#{DirSpecs.nonexistent}/subdir" }.should raise_error(SystemCallError)
  end

  it "raises Errno::EEXIST if the specified directory already exists" do
    -> { Dir.mkdir("#{DirSpecs.mock_dir}/dir") }.should raise_error(Errno::EEXIST)
  end

  it "raises Errno::EEXIST if the argument points to the existing file" do
    -> { Dir.mkdir("#{DirSpecs.mock_dir}/file_one.ext") }.should raise_error(Errno::EEXIST)
  end
end

# The permissions flag are not supported on Windows as stated in documentation:
# The permissions may be modified by the value of File.umask, and are ignored on NT.
platform_is_not :windows do
  as_user do
    describe "Dir.mkdir" do
      before :each do
        @dir = tmp "noperms"
      end

      after :each do
        File.chmod 0777, @dir
        rm_r @dir
      end

      it "raises a SystemCallError when lacking adequate permissions in the parent dir" do
        Dir.mkdir @dir, 0000

        -> { Dir.mkdir "#{@dir}/subdir" }.should raise_error(SystemCallError)
      end
    end
  end
end
