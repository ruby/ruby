require_relative '../../../../spec_helper'
require_relative 'fixtures/classes'

describe 'Thread::Backtrace::Location#absolute_path' do
  before :each do
    @frame = ThreadBacktraceLocationSpecs.locations[0]
  end

  it 'returns the absolute path of the call frame' do
    @frame.absolute_path.should == File.realpath(__FILE__)
  end

  it 'returns an absolute path when using a relative main script path' do
    script = fixture(__FILE__, 'absolute_path_main.rb')
    Dir.chdir(File.dirname(script)) do
      ruby_exe('absolute_path_main.rb').should == "absolute_path_main.rb\n#{script}\n"
    end
  end

  context "when used in eval with a given filename" do
    it "returns filename" do
      code = "caller_locations(0)[0].absolute_path"
      eval(code, nil, "foo.rb").should == "foo.rb"
      eval(code, nil, "foo/bar.rb").should == "foo/bar.rb"
    end
  end

  context "when used in #method_added" do
    it "returns the user filename that defined the method" do
      path = fixture(__FILE__, "absolute_path_method_added.rb")
      load path
      locations = ScratchPad.recorded
      locations[0].absolute_path.should == path
      # Make sure it's from the class body, not from the file top-level
      locations[0].label.should include 'MethodAddedAbsolutePath'
    end
  end

  context "when used in a core method" do
    it "returns nil" do
      location = nil
      tap { location = caller_locations(1, 1)[0] }
      location.label.should == "tap"
      if location.path.start_with?("<internal:")
        location.absolute_path.should == nil
      else
        location.absolute_path.should == File.realpath(__FILE__)
      end
    end
  end

  context "canonicalization" do
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
end
