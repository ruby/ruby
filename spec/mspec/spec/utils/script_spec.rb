require 'spec_helper'
require 'mspec/utils/script'
require 'mspec/runner/mspec'
require 'mspec/runner/filters'
require 'mspec/runner/actions/filter'

describe MSpecScript, ".config" do
  it "returns a Hash" do
    MSpecScript.config.should be_kind_of(Hash)
  end
end

describe MSpecScript, ".set" do
  it "sets the config hash key, value" do
    MSpecScript.set :a, 10
    MSpecScript.config[:a].should == 10
  end
end

describe MSpecScript, ".get" do
  it "gets the config hash value for a key" do
    MSpecScript.set :a, 10
    MSpecScript.get(:a).should == 10
  end
end

describe MSpecScript, "#config" do
  it "returns the MSpecScript config hash" do
    MSpecScript.set :b, 5
    MSpecScript.new.config[:b].should == 5
  end

  it "returns the MSpecScript config hash from subclasses" do
    class MSSClass < MSpecScript; end
    MSpecScript.set :b, 5
    MSSClass.new.config[:b].should == 5
  end
end

describe MSpecScript, "#load_default" do
  before :all do
    @verbose = $VERBOSE
    $VERBOSE = nil
  end

  after :all do
    $VERBOSE = @verbose
  end

  before :each do
    @version = RUBY_VERSION
    if Object.const_defined? :RUBY_ENGINE
      @engine = Object.const_get :RUBY_ENGINE
    end
    @script = MSpecScript.new
    MSpecScript.stub(:new).and_return(@script)
  end

  after :each do
    Object.const_set :RUBY_VERSION, @version
    Object.const_set :RUBY_ENGINE, @engine if @engine
  end

  it "attempts to load 'default.mspec'" do
    @script.stub(:try_load)
    @script.should_receive(:try_load).with('default.mspec').and_return(true)
    @script.load_default
  end

  it "attempts to load a config file based on RUBY_ENGINE and RUBY_VERSION" do
    Object.const_set :RUBY_ENGINE, "ybur"
    Object.const_set :RUBY_VERSION, "1.8.9"
    default = "ybur.1.8.mspec"
    @script.should_receive(:try_load).with('default.mspec').and_return(false)
    @script.should_receive(:try_load).with(default)
    @script.should_receive(:try_load).with('ybur.mspec')
    @script.load_default
  end
end

describe MSpecScript, ".main" do
  before :each do
    @script = double("MSpecScript").as_null_object
    MSpecScript.stub(:new).and_return(@script)
    # Do not require full mspec as it would conflict with RSpec
    MSpecScript.should_receive(:require).with('mspec')
  end

  it "creates an instance of MSpecScript" do
    MSpecScript.should_receive(:new).and_return(@script)
    MSpecScript.main
  end

  it "attempts to load the default config" do
    @script.should_receive(:load_default)
    MSpecScript.main
  end

  it "attempts to load the '~/.mspecrc' script" do
    @script.should_receive(:try_load).with('~/.mspecrc')
    MSpecScript.main
  end

  it "calls the #options method on the script" do
    @script.should_receive(:options)
    MSpecScript.main
  end

  it "calls the #signals method on the script" do
    @script.should_receive(:signals)
    MSpecScript.main
  end

  it "calls the #register method on the script" do
    @script.should_receive(:register)
    MSpecScript.main
  end

  it "calls the #setup_env method on the script" do
    @script.should_receive(:setup_env)
    MSpecScript.main
  end

  it "calls the #run method on the script" do
    @script.should_receive(:run)
    MSpecScript.main
  end
end

describe MSpecScript, "#initialize" do
  before :each do
    @config = MSpecScript.new.config
  end

  it "sets the default config values" do
    @config[:formatter].should  == nil
    @config[:includes].should   == []
    @config[:excludes].should   == []
    @config[:patterns].should   == []
    @config[:xpatterns].should  == []
    @config[:tags].should       == []
    @config[:xtags].should      == []
    @config[:atags].should      == []
    @config[:astrings].should   == []
    @config[:abort].should      == true
    @config[:config_ext].should == '.mspec'
  end
end

describe MSpecScript, "#load" do
  before :each do
    File.stub(:exist?).and_return(false)
    @script = MSpecScript.new
    @file = "default.mspec"
    @base = "default"
  end

  it "attempts to locate the file through the expanded path name" do
    File.should_receive(:expand_path).with(@file, ".").and_return(@file)
    File.should_receive(:exist?).with(@file).and_return(true)
    Kernel.should_receive(:load).with(@file).and_return(:loaded)
    @script.load(@file).should == :loaded
  end

  it "appends config[:config_ext] to the name and attempts to locate the file through the expanded path name" do
    File.should_receive(:expand_path).with(@base, ".").and_return(@base)
    File.should_receive(:expand_path).with(@base, "spec").and_return(@base)
    File.should_receive(:expand_path).with(@file, ".").and_return(@file)
    File.should_receive(:exist?).with(@base).and_return(false)
    File.should_receive(:exist?).with(@file).and_return(true)
    Kernel.should_receive(:load).with(@file).and_return(:loaded)
    @script.load(@base).should == :loaded
  end

  it "attempts to locate the file in '.'" do
    path = File.expand_path @file, "."
    File.should_receive(:exist?).with(path).and_return(true)
    Kernel.should_receive(:load).with(path).and_return(:loaded)
    @script.load(@file).should == :loaded
  end

  it "appends config[:config_ext] to the name and attempts to locate the file in '.'" do
    path = File.expand_path @file, "."
    File.should_receive(:exist?).with(path).and_return(true)
    Kernel.should_receive(:load).with(path).and_return(:loaded)
    @script.load(@base).should == :loaded
  end

  it "attempts to locate the file in 'spec'" do
    path = File.expand_path @file, "spec"
    File.should_receive(:exist?).with(path).and_return(true)
    Kernel.should_receive(:load).with(path).and_return(:loaded)
    @script.load(@file).should == :loaded
  end

  it "appends config[:config_ext] to the name and attempts to locate the file in 'spec'" do
    path = File.expand_path @file, "spec"
    File.should_receive(:exist?).with(path).and_return(true)
    Kernel.should_receive(:load).with(path).and_return(:loaded)
    @script.load(@base).should == :loaded
  end

  it "loads a given file only once" do
    path = File.expand_path @file, "spec"
    File.should_receive(:exist?).with(path).and_return(true)
    Kernel.should_receive(:load).once.with(path).and_return(:loaded)
    @script.load(@base).should == :loaded
    @script.load(@base).should == true
  end
end

describe MSpecScript, "#custom_options" do
  before :each do
    @script = MSpecScript.new
  end

  after :each do
  end

  it "prints 'None'" do
    options = double("options")
    options.should_receive(:doc).with("   No custom options registered")
    @script.custom_options options
  end
end

describe MSpecScript, "#register" do
  before :each do
    @script = MSpecScript.new

    @formatter = double("formatter").as_null_object
    @script.config[:formatter] = @formatter
  end

  it "creates and registers the formatter" do
    @formatter.should_receive(:new).and_return(@formatter)
    @formatter.should_receive(:register)
    @script.register
  end

  it "does not register the formatter if config[:formatter] is false" do
    @script.config[:formatter] = false
    @script.register
  end

  it "calls #custom_register" do
    @script.should_receive(:custom_register)
    @script.register
  end

  it "registers :formatter with the formatter instance" do
    @formatter.stub(:new).and_return(@formatter)
    MSpec.should_receive(:store).with(:formatter, @formatter)
    @script.register
  end

  it "does not register :formatter if config[:formatter] is false" do
    @script.config[:formatter] = false
    MSpec.should_not_receive(:store)
    @script.register
  end
end

describe MSpecScript, "#register" do
  before :each do
    @script = MSpecScript.new

    @formatter = double("formatter").as_null_object
    @script.config[:formatter] = @formatter

    @filter = double("filter")
    @filter.should_receive(:register)

    @ary = ["some", "spec"]
  end

  it "creates and registers a MatchFilter for include specs" do
    MatchFilter.should_receive(:new).with(:include, *@ary).and_return(@filter)
    @script.config[:includes] = @ary
    @script.register
  end

  it "creates and registers a MatchFilter for excluded specs" do
    MatchFilter.should_receive(:new).with(:exclude, *@ary).and_return(@filter)
    @script.config[:excludes] = @ary
    @script.register
  end

  it "creates and registers a RegexpFilter for include specs" do
    RegexpFilter.should_receive(:new).with(:include, *@ary).and_return(@filter)
    @script.config[:patterns] = @ary
    @script.register
  end

  it "creates and registers a RegexpFilter for excluded specs" do
    RegexpFilter.should_receive(:new).with(:exclude, *@ary).and_return(@filter)
    @script.config[:xpatterns] = @ary
    @script.register
  end

  it "creates and registers a TagFilter for include specs" do
    TagFilter.should_receive(:new).with(:include, *@ary).and_return(@filter)
    @script.config[:tags] = @ary
    @script.register
  end

  it "creates and registers a TagFilter for excluded specs" do
    TagFilter.should_receive(:new).with(:exclude, *@ary).and_return(@filter)
    @script.config[:xtags] = @ary
    @script.register
  end

  it "creates and registers a ProfileFilter for include specs" do
    ProfileFilter.should_receive(:new).with(:include, *@ary).and_return(@filter)
    @script.config[:profiles] = @ary
    @script.register
  end

  it "creates and registers a ProfileFilter for excluded specs" do
    ProfileFilter.should_receive(:new).with(:exclude, *@ary).and_return(@filter)
    @script.config[:xprofiles] = @ary
    @script.register
  end
end

describe MSpecScript, "#signals" do
  before :each do
    @script = MSpecScript.new
    @abort = @script.config[:abort]
  end

  after :each do
    @script.config[:abort] = @abort
  end

  it "traps the INT signal if config[:abort] is true" do
    Signal.should_receive(:trap).with("INT")
    @script.config[:abort] = true
    @script.signals
  end

  it "does not trap the INT signal if config[:abort] is not true" do
    Signal.should_not_receive(:trap).with("INT")
    @script.config[:abort] = false
    @script.signals
  end
end

describe MSpecScript, "#entries" do
  before :each do
    @script = MSpecScript.new

    File.stub(:realpath).and_return("name")
    File.stub(:file?).and_return(false)
    File.stub(:directory?).and_return(false)
  end

  it "returns the pattern in an array if it is a file" do
    File.should_receive(:realpath).with("file").and_return("file/expanded.rb")
    File.should_receive(:file?).with("file/expanded.rb").and_return(true)
    @script.entries("file").should == ["file/expanded.rb"]
  end

  it "returns Dir['pattern/**/*_spec.rb'] if pattern is a directory" do
    File.should_receive(:directory?).with("name").and_return(true)
    File.stub(:realpath).and_return("name", "name/**/*_spec.rb")
    Dir.should_receive(:[]).with("name/**/*_spec.rb").and_return(["dir1", "dir2"])
    @script.entries("name").should == ["dir1", "dir2"]
  end

  it "aborts if pattern cannot be resolved to a file nor a directory" do
    @script.should_receive(:abort)
    @script.entries("pattern")
  end

  describe "with config[:prefix] set" do
    before :each do
      prefix = "prefix/dir"
      @script.config[:prefix] = prefix
      @name = prefix + "/name"
    end

    it "returns the pattern in an array if it is a file" do
      name = "#{@name}.rb"
      File.should_receive(:realpath).with(name).and_return(name)
      File.should_receive(:file?).with(name).and_return(true)
      @script.entries("name.rb").should == [name]
    end

    it "returns Dir['pattern/**/*_spec.rb'] if pattern is a directory" do
      File.stub(:realpath).and_return(@name, @name+"/**/*_spec.rb")
      File.should_receive(:directory?).with(@name).and_return(true)
      Dir.should_receive(:[]).with(@name + "/**/*_spec.rb").and_return(["dir1", "dir2"])
      @script.entries("name").should == ["dir1", "dir2"]
    end

    it "aborts if pattern cannot be resolved to a file nor a directory" do
      @script.should_receive(:abort)
      @script.entries("pattern")
    end
  end
end

describe MSpecScript, "#files" do
  before :each do
    @script = MSpecScript.new
  end

  it "accumulates the values returned by #entries" do
    @script.should_receive(:entries).and_return(["file1"], ["file2"])
    @script.files(["a", "b"]).should == ["file1", "file2"]
  end

  it "strips a leading '^' and removes the values returned by #entries" do
    @script.should_receive(:entries).and_return(["file1"], ["file2"], ["file1"])
    @script.files(["a", "b", "^a"]).should == ["file2"]
  end

  it "processes the array elements in order" do
    @script.should_receive(:entries).and_return(["file1"], ["file1"], ["file2"])
    @script.files(["^a", "a", "b"]).should == ["file1", "file2"]
  end
end

describe MSpecScript, "#files" do
  before :each do
    MSpecScript.set :files, ["file1", "file2"]

    @script = MSpecScript.new
  end

  after :each do
    MSpecScript.config.delete :files
  end

  it "looks up items with leading ':' in the config object" do
    @script.should_receive(:entries).and_return(["file1"], ["file2"])
    @script.files([":files"]).should == ["file1", "file2"]
  end

  it "aborts if the config key is not set" do
    @script.should_receive(:abort).with("Key :all_files not found in mspec config.")
    @script.files([":all_files"])
  end
end

describe MSpecScript, "#setup_env" do
  before :each do
    @script = MSpecScript.new
    @options, @config = new_option
    @script.stub(:config).and_return(@config)
  end

  after :each do
  end

  it "sets MSPEC_RUNNER = '1' in the environment" do
    ENV["MSPEC_RUNNER"] = "0"
    @script.setup_env
    ENV["MSPEC_RUNNER"].should == "1"
  end

  it "sets RUBY_EXE = config[:target] in the environment" do
    ENV["RUBY_EXE"] = nil
    @script.setup_env
    ENV["RUBY_EXE"].should == @config[:target]
  end

  it "sets RUBY_FLAGS = config[:flags] in the environment" do
    ENV["RUBY_FLAGS"] = nil
    @config[:flags] = ["-w", "-Q"]
    @script.setup_env
    ENV["RUBY_FLAGS"].should == "-w -Q"
  end
end
