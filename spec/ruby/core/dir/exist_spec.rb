require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Dir.exist?" do
  before :all do
    DirSpecs.create_mock_dirs
  end

  after :all do
    DirSpecs.delete_mock_dirs
  end

  it "returns true if the given directory exists" do
    Dir.exist?(__dir__).should == true
  end

  it "returns true for '.'" do
    Dir.exist?('.').should == true
  end

  it "returns true for '..'" do
    Dir.exist?('..').should == true
  end

  it "understands non-ASCII paths" do
    subdir = File.join(tmp("\u{9876}\u{665}"))
    Dir.exist?(subdir).should == false
    Dir.mkdir(subdir)
    Dir.exist?(subdir).should == true
    Dir.rmdir(subdir)
  end

  it "understands relative paths" do
    Dir.exist?(__dir__ + '/../').should == true
  end

  it "returns false if the given directory doesn't exist" do
    Dir.exist?('y26dg27n2nwjs8a/').should == false
  end

  it "doesn't require the name to have a trailing slash" do
    dir = __dir__
    dir.sub!(/\/$/,'')
    Dir.exist?(dir).should == true
  end

  it "doesn't expand paths" do
    skip "$HOME not valid directory" unless ENV['HOME'] && File.directory?(ENV['HOME'])
    Dir.exist?(File.expand_path('~')).should == true
    Dir.exist?('~').should == false
  end

  it "returns false if the argument exists but is a file" do
    File.should.exist?(__FILE__)
    Dir.exist?(__FILE__).should == false
  end

  it "doesn't set $! when file doesn't exist" do
    Dir.exist?("/path/to/non/existent/dir")
    $!.should == nil
  end

  it "calls #to_path on non String arguments" do
    p = mock('path')
    p.should_receive(:to_path).and_return(__dir__)
    Dir.exist?(p)
  end
end

describe "Dir.exists?" do
  it "has been removed" do
    Dir.should_not.respond_to?(:exists?)
  end
end
