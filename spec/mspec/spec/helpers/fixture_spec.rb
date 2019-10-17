require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'

describe Object, "#fixture" do
  before :each do
    @dir = File.realpath("..", __FILE__)
  end

  it "returns the expanded path to a fixture file" do
    name = fixture(__FILE__, "subdir", "file.txt")
    name.should == "#{@dir}/fixtures/subdir/file.txt"
  end

  it "omits '/shared' if it is the suffix of the directory string" do
    name = fixture("#{@dir}/shared/file.rb", "subdir", "file.txt")
    name.should == "#{@dir}/fixtures/subdir/file.txt"
  end

  it "does not append '/fixtures' if it is the suffix of the directory string" do
    commands_dir = "#{File.dirname(@dir)}/commands"
    name = fixture("#{commands_dir}/fixtures/file.rb", "subdir", "file.txt")
    name.should == "#{commands_dir}/fixtures/subdir/file.txt"
  end
end
