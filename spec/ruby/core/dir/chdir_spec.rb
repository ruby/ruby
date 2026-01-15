require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Dir.chdir" do
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

  it "defaults to $HOME with no arguments" do
    skip "$HOME not valid directory" unless ENV['HOME'] && File.directory?(ENV['HOME'])

    Dir.chdir
    current_dir = Dir.pwd

    Dir.chdir(ENV['HOME'])
    home = Dir.pwd
    current_dir.should == home
  end

  it "changes to the specified directory" do
    Dir.chdir DirSpecs.mock_dir
    Dir.pwd.should == DirSpecs.mock_dir
  end

  it "returns 0 when successfully changing directory" do
    Dir.chdir(@original).should == 0
  end

  it "calls #to_str on the argument if it's not a String" do
    obj = mock('path')
    obj.should_receive(:to_str).and_return(Dir.pwd)
    Dir.chdir(obj)
  end

  it "calls #to_str on the argument if it's not a String and a block is given" do
    obj = mock('path')
    obj.should_receive(:to_str).and_return(Dir.pwd)
    Dir.chdir(obj) { }
  end

  it "calls #to_path on the argument if it's not a String" do
    obj = mock('path')
    obj.should_receive(:to_path).and_return(Dir.pwd)
    Dir.chdir(obj)
  end

  it "prefers #to_path over #to_str" do
    obj = Class.new do
      def to_path; Dir.pwd; end
      def to_str;  DirSpecs.mock_dir; end
    end
    Dir.chdir(obj.new)
    Dir.pwd.should == @original
  end

  it "returns the value of the block when a block is given" do
    Dir.chdir(@original) { :block_value }.should == :block_value
  end

  it "defaults to the home directory when given a block but no argument" do
    skip "$HOME not valid directory" unless ENV['HOME'] && File.directory?(ENV['HOME'])

    # Windows will return a path with forward slashes for ENV["HOME"] so we have
    # to compare the route representations returned by Dir.chdir.
    current_dir = ""
    Dir.chdir { current_dir = Dir.pwd }

    Dir.chdir(ENV['HOME'])
    home = Dir.pwd
    current_dir.should == home
  end

  it "changes to the specified directory for the duration of the block" do
    ar = Dir.chdir(DirSpecs.mock_dir) { |dir| [dir, Dir.pwd] }
    ar.should == [DirSpecs.mock_dir, DirSpecs.mock_dir]

    Dir.pwd.should == @original
  end

  it "raises an Errno::ENOENT if the directory does not exist" do
    -> { Dir.chdir DirSpecs.nonexistent }.should raise_error(Errno::ENOENT)
    -> { Dir.chdir(DirSpecs.nonexistent) { } }.should raise_error(Errno::ENOENT)
  end

  it "raises an Errno::ENOENT if the original directory no longer exists" do
    dir1 = tmp('testdir1')
    dir2 = tmp('testdir2')
    Dir.should_not.exist?(dir1)
    Dir.should_not.exist?(dir2)
    Dir.mkdir dir1
    Dir.mkdir dir2
    begin
      -> {
        Dir.chdir dir1 do
          Dir.chdir(dir2) { Dir.unlink dir1 }
        end
      }.should raise_error(Errno::ENOENT)
    ensure
      Dir.unlink dir1 if Dir.exist?(dir1)
      Dir.unlink dir2 if Dir.exist?(dir2)
    end
  end

  it "always returns to the original directory when given a block" do
    begin
      Dir.chdir(DirSpecs.mock_dir) do
        raise StandardError, "something bad happened"
      end
    rescue StandardError
    end

    Dir.pwd.should == @original
  end
end

ruby_version_is '3.3' do
  describe "Dir#chdir" do
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

    it "changes the current working directory to self" do
      dir = Dir.new(DirSpecs.mock_dir)
      dir.chdir
      Dir.pwd.should == DirSpecs.mock_dir
    ensure
      dir.close
    end

    it "changes the current working directory to self for duration of the block when a block is given" do
      dir = Dir.new(DirSpecs.mock_dir)
      pwd_in_block = nil

      dir.chdir { pwd_in_block = Dir.pwd }

      pwd_in_block.should == DirSpecs.mock_dir
      Dir.pwd.should == @original
    ensure
      dir.close
    end

    it "returns 0 when successfully changing directory" do
      dir = Dir.new(DirSpecs.mock_dir)
      dir.chdir.should == 0
    ensure
      dir.close
    end

    it "returns the value of the block when a block is given" do
      dir = Dir.new(DirSpecs.mock_dir)
      dir.chdir { :block_value }.should == :block_value
    ensure
      dir.close
    end

    platform_is_not :windows do
      it "does not raise an Errno::ENOENT if the original directory no longer exists" do
        dir_name1 = tmp('testdir1')
        dir_name2 = tmp('testdir2')
        Dir.should_not.exist?(dir_name1)
        Dir.should_not.exist?(dir_name2)
        Dir.mkdir dir_name1
        Dir.mkdir dir_name2

        dir2 = Dir.new(dir_name2)

        begin
          Dir.chdir(dir_name1) do
            dir2.chdir { Dir.unlink dir_name1 }
          end
          Dir.pwd.should == @original
        ensure
          Dir.unlink dir_name1 if Dir.exist?(dir_name1)
          Dir.unlink dir_name2 if Dir.exist?(dir_name2)
        end
      ensure
        dir2.close
      end
    end

    it "always returns to the original directory when given a block" do
      dir = Dir.new(DirSpecs.mock_dir)

      begin
        dir.chdir do
          raise StandardError, "something bad happened"
        end
      rescue StandardError
      end

      Dir.pwd.should == @original
    ensure
      dir.close
    end
  end
end
