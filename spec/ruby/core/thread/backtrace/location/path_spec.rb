require_relative '../../../../spec_helper'
require_relative 'fixtures/classes'

describe 'Thread::Backtrace::Location#path' do
  context 'outside a main script' do
    it 'returns an absolute path' do
      frame = ThreadBacktraceLocationSpecs.locations[0]

      frame.path.should == __FILE__
    end
  end

  context 'in a main script' do
    before do
      @script = fixture(__FILE__, 'main.rb')
    end

    context 'when the script is in the working directory' do
      before do
        @directory = File.dirname(@script)
      end

      context 'when using a relative script path' do
        it 'returns a path relative to the working directory' do
          Dir.chdir(@directory) {
            ruby_exe('main.rb')
          }.should == 'main.rb'
        end
      end

      context 'when using an absolute script path' do
        it 'returns an absolute path' do
          Dir.chdir(@directory) {
            ruby_exe(@script)
          }.should == @script
        end
      end
    end

    context 'when the script is in a sub directory of the working directory' do
      context 'when using a relative script path' do
        it 'returns a path relative to the working directory' do
          path      = 'fixtures/main.rb'
          directory = File.dirname(__FILE__)
          Dir.chdir(directory) {
            ruby_exe(path)
          }.should == path
        end
      end

      context 'when using an absolute script path' do
        it 'returns an absolute path' do
          ruby_exe(@script).should == @script
        end
      end
    end

    context 'when the script is outside of the working directory' do
      before :each do
        @parent_dir = tmp('path_outside_pwd')
        @sub_dir    = File.join(@parent_dir, 'sub')
        @script     = File.join(@parent_dir, 'main.rb')
        source      = fixture(__FILE__, 'main.rb')

        mkdir_p(@sub_dir)

        cp(source, @script)
      end

      after :each do
        rm_r(@parent_dir)
      end

      context 'when using a relative script path' do
        it 'returns a path relative to the working directory' do
          Dir.chdir(@sub_dir) {
            ruby_exe('../main.rb')
          }.should == '../main.rb'
        end
      end

      context 'when using an absolute path' do
        it 'returns an absolute path' do
          ruby_exe(@script).should == @script
        end
      end
    end
  end

  it 'should be the same path as in #to_s, including for core methods' do
    # Get the caller_locations from a call made into a core library method
    locations = [:non_empty].map { caller_locations }[0]

    locations.each do |location|
      filename = location.to_s[/^(.+):\d+:/, 1]
      path = location.path

      path.should == filename
    end
  end

  context "canonicalization" do
    platform_is_not :windows do
      before :each do
        @file = fixture(__FILE__, "path.rb")
        @symlink = tmp("symlink.rb")
        File.symlink(@file, @symlink)
        ScratchPad.record []
      end

      after :each do
        rm_r @symlink
      end

      it "returns a non-canonical path with symlinks, the same as __FILE__" do
        realpath = File.realpath(@symlink)
        realpath.should_not == @symlink

        load @symlink
        ScratchPad.recorded.should == [@symlink, @symlink]
      end
    end
  end
end
