require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Dir.open" do
  before :all do
    DirSpecs.create_mock_dirs
  end

  after :all do
    DirSpecs.delete_mock_dirs
  end

  it "returns a Dir instance representing the specified directory" do
    dir = Dir.open(DirSpecs.mock_dir)
    dir.should.is_a?(Dir)
    dir.close
  end

  it "raises a SystemCallError if the directory does not exist" do
    -> do
      Dir.open(DirSpecs.nonexistent)
    end.should.raise(SystemCallError)
  end

  it "may take a block which is yielded to with the Dir instance" do
    Dir.open(DirSpecs.mock_dir) {|dir| dir.should.is_a?(Dir)}
  end

  it "returns the value of the block if a block is given" do
    Dir.open(DirSpecs.mock_dir) {|dir| :value }.should == :value
  end

  it "closes the Dir instance when the block exits if given a block" do
    closed_dir = Dir.open(DirSpecs.mock_dir) { |dir| dir }
    -> { closed_dir.read }.should.raise(IOError)
  end

  it "closes the Dir instance when the block exits the block even due to an exception" do
    closed_dir = nil

    -> do
      Dir.open(DirSpecs.mock_dir) do |dir|
        closed_dir = dir
        raise "dir specs"
      end
    end.should.raise(RuntimeError, "dir specs")

    -> { closed_dir.read }.should.raise(IOError)
  end

  it "calls #to_path on non-String arguments" do
    p = mock('path')
    p.should_receive(:to_path).and_return(DirSpecs.mock_dir)
    Dir.open(p) { true }
  end

  it "accepts an options Hash" do
    dir = Dir.open(DirSpecs.mock_dir, encoding: "utf-8") {|d| d }
    dir.should.is_a?(Dir)
  end

  it "calls #to_hash to convert the options object" do
    options = mock("dir_open")
    options.should_receive(:to_hash).and_return({ encoding: Encoding::UTF_8 })

    dir = Dir.open(DirSpecs.mock_dir, **options) {|d| d }
    dir.should.is_a?(Dir)
  end

  it "ignores the :encoding option if it is nil" do
    dir = Dir.open(DirSpecs.mock_dir, encoding: nil) {|d| d }
    dir.should.is_a?(Dir)
  end

  platform_is_not :windows do
    it 'sets the close-on-exec flag for the directory file descriptor' do
      Dir.open(DirSpecs.mock_dir) do |dir|
        io = IO.for_fd(dir.fileno)
        io.autoclose = false
        io.should.close_on_exec?
      end
    end
  end
end
