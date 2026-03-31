require_relative '../spec_helper'

describe 'The -S command line option' do
  before :each do
    @bin = fixture(__FILE__, "bin")
    @path = [ENV['PATH'], @bin].join(File::PATH_SEPARATOR)
  end

  platform_is_not :windows do
    # On VirtualBox shared directory (vboxsf) all files are world writable
    # and MRI shows warning when including world writable path in ENV['PATH'].
    # This is why we are using /success$/ matching in the following cases.

    it "runs launcher found in RUBYPATH, but only code after the first /\#!.*ruby.*/-ish line in target file" do
      result = ruby_exe(nil, options: '-S hybrid_launcher.sh', env: { 'RUBYPATH' => @bin }, args: '2>&1')
      result.should =~ /success$/
    end

    it "runs launcher found in PATH, but only code after the first /\#!.*ruby.*/-ish line in target file" do
      result = ruby_exe(nil, options: '-S hybrid_launcher.sh', env: { 'PATH' => @path }, args: '2>&1')
      result.should =~ /success$/
    end

    it "runs launcher found in RUBYPATH" do
      result = ruby_exe(nil, options: '-S launcher.rb', env: { 'RUBYPATH' => @bin }, args: '2>&1')
      result.should =~ /success$/
    end

    it "runs launcher found in PATH" do
      result = ruby_exe(nil, options: '-S launcher.rb', env: { 'PATH' => @path }, args: '2>&1')
      result.should =~ /success$/
    end

    it "runs launcher found in RUBYPATH and sets the exit status to 1 if it fails" do
      result = ruby_exe(nil, options: '-S dash_s_fail', env: { 'RUBYPATH' => @bin }, args: '2>&1', exit_status: 1)
      result.should =~ /\bdie\b/
      $?.exitstatus.should == 1
    end

    it "runs launcher found in PATH and sets the exit status to 1 if it fails" do
      result = ruby_exe(nil, options: '-S dash_s_fail', env: { 'PATH' => @path }, args: '2>&1', exit_status: 1)
      result.should =~ /\bdie\b/
      $?.exitstatus.should == 1
    end

    ruby_version_is "4.1" do
      describe "if the script name contains separator" do
        before(:each) do
          @bin = File.dirname(@bin)
          @path = [ENV['PATH'], @bin].join(File::PATH_SEPARATOR)
        end

        it "does not search launcher in RUBYPATH" do
          result = ruby_exe(nil, options: '-S bin/launcher.rb', env: { 'RUBYPATH' => @bin }, args: '2>&1', exit_status: 1)
          result.should =~ /LoadError/
          $?.should_not.success?
        end

        it "does not search launcher in PATH" do
          result = ruby_exe(nil, options: '-S bin/launcher.rb', env: { 'PATH' => @path }, args: '2>&1', exit_status: 1)
          result.should =~ /LoadError/
          $?.should_not.success?
        end
      end
    end
  end
end
