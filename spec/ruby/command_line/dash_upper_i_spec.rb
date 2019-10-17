require_relative '../spec_helper'

describe "The -I command line option" do
  before :each do
    @script = fixture __FILE__, "loadpath.rb"
  end

  it "adds the path to the load path ($:)" do
    ruby_exe(@script, options: "-I fixtures").should include("fixtures")
  end

  it "adds the path at the front of $LOAD_PATH" do
    lines = ruby_exe(@script, options: "-I fixtures").lines
    if PlatformGuard.implementation? :ruby
      # In a MRI checkout, $PWD ends up as the first entry in $LOAD_PATH.
      # So just assert that it's at the beginning.
      idx = lines.index { |l| l.include?("fixtures") }
      idx.should < 2
      idx.should < lines.size-1
    else
      lines[0].should include("fixtures")
    end
  end

  it "adds the path expanded from CWD to $LOAD_PATH" do
    ruby_exe(@script, options: "-I fixtures").lines.should include "#{Dir.pwd}/fixtures\n"
  end

  it "expands a path from CWD even if it does not exist" do
    ruby_exe(@script, options: "-I not_exist/not_exist").lines.should include "#{Dir.pwd}/not_exist/not_exist\n"
  end
end

platform_is_not :windows do
  describe "The -I command line option" do
    before :each do
      @script = fixture __FILE__, "loadpath.rb"
      @fixtures = File.dirname(@script)
      @symlink = tmp("loadpath_symlink")
      File.symlink(@fixtures, @symlink)
    end

    after :each do
      rm_r @symlink
    end

    it "does not expand symlinks" do
      ruby_exe(@script, options: "-I #{@symlink}").lines.should include "#{@symlink}\n"
    end
  end
end
