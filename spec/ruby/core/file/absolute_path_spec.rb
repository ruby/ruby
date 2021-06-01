require_relative '../../spec_helper'

ruby_version_is "2.7" do
  describe "File.absolute_path?" do
    before :each do
      @abs = File.expand_path(__FILE__)
    end

    it "returns true if it's an absolute pathname" do
      File.absolute_path?(@abs).should be_true
    end

    it "returns false if it's a relative path" do
      File.absolute_path?(File.basename(__FILE__)).should be_false
    end

    it "returns false if it's a tricky relative path" do
      File.absolute_path?("C:foo\\bar").should be_false
    end

    it "does not expand '~' to a home directory." do
      File.absolute_path?('~').should be_false
    end

    it "does not expand '~user' to a home directory." do
      path = File.dirname(@abs)
      Dir.chdir(path) do
        File.absolute_path?('~user').should be_false
      end
    end

    it "calls #to_path on its argument" do
      mock = mock_to_path(File.expand_path(__FILE__))

      File.absolute_path?(mock).should be_true
    end

    platform_is_not :windows do
      it "takes into consideration the platform's root" do
        File.absolute_path?("C:\\foo\\bar").should be_false
        File.absolute_path?("C:/foo/bar").should be_false
        File.absolute_path?("/foo/bar\\baz").should be_true
      end
    end

    platform_is :windows do
      it "takes into consideration the platform path separator(s)" do
        File.absolute_path?("C:\\foo\\bar").should be_true
        File.absolute_path?("C:/foo/bar").should be_true
        File.absolute_path?("/foo/bar\\baz").should be_false
      end
    end
  end
end

describe "File.absolute_path" do
  before :each do
    @abs = File.expand_path(__FILE__)
  end

  it "returns the argument if it's an absolute pathname" do
    File.absolute_path(@abs).should == @abs
  end

  it "resolves paths relative to the current working directory" do
    path = File.dirname(@abs)
    Dir.chdir(path) do
      File.absolute_path('hello.txt').should == File.join(Dir.pwd, 'hello.txt')
    end
  end

  it "does not expand '~' to a home directory." do
    File.absolute_path('~').should_not == File.expand_path('~')
  end

  platform_is_not :windows do
    it "does not expand '~' when given dir argument" do
      File.absolute_path('~', '/').should == '/~'
    end
  end

  it "does not expand '~user' to a home directory." do
    path = File.dirname(@abs)
    Dir.chdir(path) do
      File.absolute_path('~user').should == File.join(Dir.pwd, '~user')
    end
  end

  it "accepts a second argument of a directory from which to resolve the path" do
    File.absolute_path(__FILE__, File.dirname(__FILE__)).should == @abs
  end

  it "calls #to_path on its argument" do
    File.absolute_path(mock_to_path(@abs)).should == @abs
  end
end
