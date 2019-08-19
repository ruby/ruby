require_relative '../../../../spec_helper'
require_relative 'fixtures/classes'

describe 'Thread::Backtrace::Location#absolute_path' do
  before :each do
    @frame = ThreadBacktraceLocationSpecs.locations[0]
  end

  it 'returns the absolute path of the call frame' do
    @frame.absolute_path.should == File.realpath(__FILE__)
  end

  context "when used in eval with a given filename" do
    it "returns filename" do
      code = "caller_locations(0)[0].absolute_path"
      eval(code, nil, "foo.rb").should == "foo.rb"
      eval(code, nil, "foo/bar.rb").should == "foo/bar.rb"
    end
  end

  platform_is_not :windows do
    before :each do
      @file = fixture(__FILE__, "absolute_path.rb")
      @symlink = tmp("symlink.rb")
      File.symlink(@file, @symlink)
      ScratchPad.record []
    end

    after :each do
      rm_r @symlink
    end

    it "returns a canonical path without symlinks, even when __FILE__ does not" do
      realpath = File.realpath(@symlink)
      realpath.should_not == @symlink

      load @symlink
      ScratchPad.recorded.should == [@symlink, realpath]
    end

    it "returns a canonical path without symlinks, even when __FILE__ is removed" do
      realpath = File.realpath(@symlink)
      realpath.should_not == @symlink

      ScratchPad << -> { rm_r(@symlink) }
      load @symlink
      ScratchPad.recorded.should == [@symlink, realpath]
    end
  end
end
