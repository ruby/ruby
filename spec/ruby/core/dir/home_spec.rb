require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Dir.home" do
  before :each do
    @home = ENV['HOME']
    ENV['HOME'] = "/rubyspec_home"
  end

  after :each do
    ENV['HOME'] = @home
  end

  describe "when called without arguments" do
    it "returns the current user's home directory, reading $HOME first" do
      Dir.home.should == "/rubyspec_home"
    end

    it "returns a non-frozen string" do
      Dir.home.should_not.frozen?
    end

    platform_is :windows do
      ruby_version_is "3.0" do
        it "returns the current user's home directory from USERPROFILE as UTF-8" do
          old_dir = ENV['USERPROFILE']
          ENV.delete 'HOME'
          ENV['USERPROFILE'] = "C:\\rubyspäc\\home"
          home = Dir.home
          home.should == "C:/rubyspäc/home"
          home.encoding.should == Encoding::UTF_8
        ensure
          ENV['USERPROFILE'] = old_dir
        end

        it "returns the current user's home directory from HOMEDRIVE + HOMEPATH as UTF-8" do
          old_dir = ENV['USERPROFILE']
          old_drive = ENV['HOMEDRIVE']
          old_path = ENV['HOMEPATH']
          ENV.delete 'HOME'
          ENV.delete 'USERPROFILE'
          ENV['HOMEDRIVE'] = "C:"
          ENV['HOMEPATH'] = "\\rubysp€c\\home"
          home = Dir.home
          home.should == "C:/rubysp€c/home"
          home.encoding.should == Encoding::UTF_8
        ensure
          ENV['USERPROFILE'] = old_dir
          ENV['HOMEDRIVE'] = old_drive
          ENV['HOMEPATH'] = old_path
        end
      end
    end
  end


  describe "when called with the current user name" do
    platform_is :solaris do
      it "returns the named user's home directory from the user database" do
        Dir.home(ENV['USER']).should == `getent passwd #{ENV['USER']}|cut -d: -f6`.chomp
      end
    end

    platform_is_not :windows, :solaris, :android, :wasi do
      it "returns the named user's home directory, from the user database" do
        Dir.home(ENV['USER']).should == `echo ~#{ENV['USER']}`.chomp
      end
    end

    it "returns a non-frozen string" do
      Dir.home(ENV['USER']).should_not.frozen?
    end
  end

  it "raises an ArgumentError if the named user doesn't exist" do
    -> { Dir.home('geuw2n288dh2k') }.should raise_error(ArgumentError)
  end
end
