require_relative '../spec_helper'

describe "The RUBYLIB environment variable" do
  before :each do
    @rubylib, ENV["RUBYLIB"] = ENV["RUBYLIB"], nil
    @pre  = @rubylib.nil? ? '' : @rubylib + File::PATH_SEPARATOR
  end

  after :each do
    ENV["RUBYLIB"] = @rubylib
  end

  it "adds a directory to $LOAD_PATH" do
    dir = tmp("rubylib/incl")
    ENV["RUBYLIB"] = @pre + dir
    paths = ruby_exe("puts $LOAD_PATH").lines.map(&:chomp)
    paths.should include(dir)
  end

  it "adds a File::PATH_SEPARATOR-separated list of directories to $LOAD_PATH" do
    dir1, dir2 = tmp("rubylib/incl1"), tmp("rubylib/incl2")
    ENV["RUBYLIB"] = @pre + "#{dir1}#{File::PATH_SEPARATOR}#{dir2}"
    paths = ruby_exe("puts $LOAD_PATH").lines.map(&:chomp)
    paths.should include(dir1)
    paths.should include(dir2)
    paths.index(dir1).should < paths.index(dir2)
  end

  it "adds the directory at the front of $LOAD_PATH" do
    dir = tmp("rubylib/incl_front")
    ENV["RUBYLIB"] = @pre + dir
    paths = ruby_exe("puts $LOAD_PATH").lines.map(&:chomp)
    paths.shift if paths.first.end_with?('/gem-rehash')
    if PlatformGuard.implementation? :ruby
      # In a MRI checkout, $PWD and some extra -I entries end up as
      # the first entries in $LOAD_PATH. So just assert that it's not last.
      idx = paths.index(dir)
      idx.should < paths.size-1
    else
      paths[0].should == dir
    end
  end

  it "adds the directory after directories added by -I" do
    dash_i_dir = tmp("dash_I_include")
    rubylib_dir = tmp("rubylib_include")
    ENV["RUBYLIB"] = @pre + rubylib_dir
    paths = ruby_exe("puts $LOAD_PATH", options: "-I #{dash_i_dir}").lines.map(&:chomp)
    paths.should include(dash_i_dir)
    paths.should include(rubylib_dir)
    paths.index(dash_i_dir).should < paths.index(rubylib_dir)
  end

  it "adds the directory after directories added by -I within RUBYOPT" do
    rubyopt_dir = tmp("rubyopt_include")
    rubylib_dir = tmp("rubylib_include")
    ENV["RUBYLIB"] = @pre + rubylib_dir
    paths = ruby_exe("puts $LOAD_PATH", env: { "RUBYOPT" => "-I#{rubyopt_dir}" }).lines.map(&:chomp)
    paths.should include(rubyopt_dir)
    paths.should include(rubylib_dir)
    paths.index(rubyopt_dir).should < paths.index(rubylib_dir)
  end

  it "keeps spaces in the value" do
    ENV["RUBYLIB"] = @pre + " rubylib/incl "
    out = ruby_exe("puts $LOAD_PATH")
    out.should include(" rubylib/incl ")
  end
end
