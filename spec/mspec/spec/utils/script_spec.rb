require 'spec_helper'
require 'mspec/utils/script'
require 'mspec/runner/mspec'
require 'mspec/runner/filters'
require 'mspec/runner/actions/filter'

RSpec.describe MSpecScript, ".config" do
  it "returns a Hash" do
    expect(MSpecScript.config).to be_kind_of(Hash)
  end
end

RSpec.describe MSpecScript, ".set" do
  it "sets the config hash key, value" do
    MSpecScript.set :a, 10
    expect(MSpecScript.config[:a]).to eq(10)
  end
end

RSpec.describe MSpecScript, ".get" do
  it "gets the config hash value for a key" do
    MSpecScript.set :a, 10
    expect(MSpecScript.get(:a)).to eq(10)
  end
end

RSpec.describe MSpecScript, "#config" do
  it "returns the MSpecScript config hash" do
    MSpecScript.set :b, 5
    expect(MSpecScript.new.config[:b]).to eq(5)
  end

  it "returns the MSpecScript config hash from subclasses" do
    class MSSClass < MSpecScript; end
    MSpecScript.set :b, 5
    expect(MSSClass.new.config[:b]).to eq(5)
  end
end

RSpec.describe MSpecScript, "#load_default" do
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
    allow(MSpecScript).to receive(:new).and_return(@script)
  end

  after :each do
    Object.const_set :RUBY_VERSION, @version
    Object.const_set :RUBY_ENGINE, @engine if @engine
  end

  it "attempts to load 'default.mspec'" do
    allow(@script).to receive(:try_load)
    expect(@script).to receive(:try_load).with('default.mspec').and_return(true)
    @script.load_default
  end

  it "attempts to load a config file based on RUBY_ENGINE and RUBY_VERSION" do
    Object.const_set :RUBY_ENGINE, "ybur"
    Object.const_set :RUBY_VERSION, "1.8.9"
    default = "ybur.1.8.mspec"
    expect(@script).to receive(:try_load).with('default.mspec').and_return(false)
    expect(@script).to receive(:try_load).with(default)
    expect(@script).to receive(:try_load).with('ybur.mspec')
    @script.load_default
  end
end

RSpec.describe MSpecScript, ".main" do
  before :each do
    @script = double("MSpecScript").as_null_object
    allow(MSpecScript).to receive(:new).and_return(@script)
    # Do not require full mspec as it would conflict with RSpec
    expect(MSpecScript).to receive(:require).with('mspec')
  end

  it "creates an instance of MSpecScript" do
    expect(MSpecScript).to receive(:new).and_return(@script)
    MSpecScript.main
  end

  it "attempts to load the default config" do
    expect(@script).to receive(:load_default)
    MSpecScript.main
  end

  it "calls the #options method on the script" do
    expect(@script).to receive(:options)
    MSpecScript.main
  end

  it "calls the #signals method on the script" do
    expect(@script).to receive(:signals)
    MSpecScript.main
  end

  it "calls the #register method on the script" do
    expect(@script).to receive(:register)
    MSpecScript.main
  end

  it "calls the #setup_env method on the script" do
    expect(@script).to receive(:setup_env)
    MSpecScript.main
  end

  it "calls the #run method on the script" do
    expect(@script).to receive(:run)
    MSpecScript.main
  end
end

RSpec.describe MSpecScript, "#initialize" do
  before :each do
    @config = MSpecScript.new.config
  end

  it "sets the default config values" do
    expect(@config[:formatter]).to  eq(nil)
    expect(@config[:includes]).to   eq([])
    expect(@config[:excludes]).to   eq([])
    expect(@config[:patterns]).to   eq([])
    expect(@config[:xpatterns]).to  eq([])
    expect(@config[:tags]).to       eq([])
    expect(@config[:xtags]).to      eq([])
    expect(@config[:atags]).to      eq([])
    expect(@config[:astrings]).to   eq([])
    expect(@config[:abort]).to      eq(true)
    expect(@config[:config_ext]).to eq('.mspec')
  end
end

RSpec.describe MSpecScript, "#load" do
  before :each do
    allow(File).to receive(:exist?).and_return(false)
    @script = MSpecScript.new
    @file = "default.mspec"
    @base = "default"
  end

  it "attempts to locate the file through the expanded path name" do
    expect(File).to receive(:expand_path).with(@file, ".").and_return(@file)
    expect(File).to receive(:exist?).with(@file).and_return(true)
    expect(Kernel).to receive(:load).with(@file).and_return(:loaded)
    expect(@script.load(@file)).to eq(:loaded)
  end

  it "appends config[:config_ext] to the name and attempts to locate the file through the expanded path name" do
    expect(File).to receive(:expand_path).with(@base, ".").and_return(@base)
    expect(File).to receive(:expand_path).with(@base, "spec").and_return(@base)
    expect(File).to receive(:expand_path).with(@file, ".").and_return(@file)
    expect(File).to receive(:exist?).with(@base).and_return(false)
    expect(File).to receive(:exist?).with(@file).and_return(true)
    expect(Kernel).to receive(:load).with(@file).and_return(:loaded)
    expect(@script.load(@base)).to eq(:loaded)
  end

  it "attempts to locate the file in '.'" do
    path = File.expand_path @file, "."
    expect(File).to receive(:exist?).with(path).and_return(true)
    expect(Kernel).to receive(:load).with(path).and_return(:loaded)
    expect(@script.load(@file)).to eq(:loaded)
  end

  it "appends config[:config_ext] to the name and attempts to locate the file in '.'" do
    path = File.expand_path @file, "."
    expect(File).to receive(:exist?).with(path).and_return(true)
    expect(Kernel).to receive(:load).with(path).and_return(:loaded)
    expect(@script.load(@base)).to eq(:loaded)
  end

  it "attempts to locate the file in 'spec'" do
    path = File.expand_path @file, "spec"
    expect(File).to receive(:exist?).with(path).and_return(true)
    expect(Kernel).to receive(:load).with(path).and_return(:loaded)
    expect(@script.load(@file)).to eq(:loaded)
  end

  it "appends config[:config_ext] to the name and attempts to locate the file in 'spec'" do
    path = File.expand_path @file, "spec"
    expect(File).to receive(:exist?).with(path).and_return(true)
    expect(Kernel).to receive(:load).with(path).and_return(:loaded)
    expect(@script.load(@base)).to eq(:loaded)
  end

  it "loads a given file only once" do
    path = File.expand_path @file, "spec"
    expect(File).to receive(:exist?).with(path).and_return(true)
    expect(Kernel).to receive(:load).once.with(path).and_return(:loaded)
    expect(@script.load(@base)).to eq(:loaded)
    expect(@script.load(@base)).to eq(true)
  end
end

RSpec.describe MSpecScript, "#custom_options" do
  before :each do
    @script = MSpecScript.new
  end

  after :each do
  end

  it "prints 'None'" do
    options = double("options")
    expect(options).to receive(:doc).with("   No custom options registered")
    @script.custom_options options
  end
end

RSpec.describe MSpecScript, "#register" do
  before :each do
    @script = MSpecScript.new

    @formatter = double("formatter").as_null_object
    @script.config[:formatter] = @formatter
  end

  it "creates and registers the formatter" do
    expect(@formatter).to receive(:new).and_return(@formatter)
    expect(@formatter).to receive(:register)
    @script.register
  end

  it "does not register the formatter if config[:formatter] is false" do
    @script.config[:formatter] = false
    @script.register
  end

  it "calls #custom_register" do
    expect(@script).to receive(:custom_register)
    @script.register
  end

  it "registers :formatter with the formatter instance" do
    allow(@formatter).to receive(:new).and_return(@formatter)
    @script.register
    expect(MSpec.formatter).to be(@formatter)
  end

  it "does not register :formatter if config[:formatter] is false" do
    @script.config[:formatter] = false
    expect(MSpec).not_to receive(:store)
    @script.register
  end
end

RSpec.describe MSpecScript, "#register" do
  before :each do
    @script = MSpecScript.new

    @formatter = double("formatter").as_null_object
    @script.config[:formatter] = @formatter

    @filter = double("filter")
    expect(@filter).to receive(:register)

    @ary = ["some", "spec"]
  end

  it "creates and registers a MatchFilter for include specs" do
    expect(MatchFilter).to receive(:new).with(:include, *@ary).and_return(@filter)
    @script.config[:includes] = @ary
    @script.register
  end

  it "creates and registers a MatchFilter for excluded specs" do
    expect(MatchFilter).to receive(:new).with(:exclude, *@ary).and_return(@filter)
    @script.config[:excludes] = @ary
    @script.register
  end

  it "creates and registers a RegexpFilter for include specs" do
    expect(RegexpFilter).to receive(:new).with(:include, *@ary).and_return(@filter)
    @script.config[:patterns] = @ary
    @script.register
  end

  it "creates and registers a RegexpFilter for excluded specs" do
    expect(RegexpFilter).to receive(:new).with(:exclude, *@ary).and_return(@filter)
    @script.config[:xpatterns] = @ary
    @script.register
  end

  it "creates and registers a TagFilter for include specs" do
    expect(TagFilter).to receive(:new).with(:include, *@ary).and_return(@filter)
    @script.config[:tags] = @ary
    @script.register
  end

  it "creates and registers a TagFilter for excluded specs" do
    expect(TagFilter).to receive(:new).with(:exclude, *@ary).and_return(@filter)
    @script.config[:xtags] = @ary
    @script.register
  end

  it "creates and registers a ProfileFilter for include specs" do
    expect(ProfileFilter).to receive(:new).with(:include, *@ary).and_return(@filter)
    @script.config[:profiles] = @ary
    @script.register
  end

  it "creates and registers a ProfileFilter for excluded specs" do
    expect(ProfileFilter).to receive(:new).with(:exclude, *@ary).and_return(@filter)
    @script.config[:xprofiles] = @ary
    @script.register
  end
end

RSpec.describe MSpecScript, "#signals" do
  before :each do
    @script = MSpecScript.new
    @abort = @script.config[:abort]
  end

  after :each do
    @script.config[:abort] = @abort
  end

  it "traps the INT signal if config[:abort] is true" do
    expect(Signal).to receive(:trap).with("INT")
    @script.config[:abort] = true
    @script.signals
  end

  it "does not trap the INT signal if config[:abort] is not true" do
    expect(Signal).not_to receive(:trap).with("INT")
    @script.config[:abort] = false
    @script.signals
  end
end

RSpec.describe MSpecScript, "#entries" do
  before :each do
    @script = MSpecScript.new

    allow(File).to receive(:realpath).and_return("name")
    allow(File).to receive(:file?).and_return(false)
    allow(File).to receive(:directory?).and_return(false)
  end

  it "returns the pattern in an array if it is a file" do
    expect(File).to receive(:realpath).with("file").and_return("file/expanded.rb")
    expect(File).to receive(:file?).with("file/expanded.rb").and_return(true)
    expect(@script.entries("file")).to eq(["file/expanded.rb"])
  end

  it "returns Dir['pattern/**/*_spec.rb'] if pattern is a directory" do
    expect(File).to receive(:directory?).with("name").and_return(true)
    allow(File).to receive(:realpath).and_return("name", "name/**/*_spec.rb")
    expect(Dir).to receive(:[]).with("name/**/*_spec.rb").and_return(["dir1", "dir2"])
    expect(@script.entries("name")).to eq(["dir1", "dir2"])
  end

  it "aborts if pattern cannot be resolved to a file nor a directory" do
    expect(@script).to receive(:abort)
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
      expect(File).to receive(:realpath).with(name).and_return(name)
      expect(File).to receive(:file?).with(name).and_return(true)
      expect(@script.entries("name.rb")).to eq([name])
    end

    it "returns Dir['pattern/**/*_spec.rb'] if pattern is a directory" do
      allow(File).to receive(:realpath).and_return(@name, @name+"/**/*_spec.rb")
      expect(File).to receive(:directory?).with(@name).and_return(true)
      expect(Dir).to receive(:[]).with(@name + "/**/*_spec.rb").and_return(["dir1", "dir2"])
      expect(@script.entries("name")).to eq(["dir1", "dir2"])
    end

    it "aborts if pattern cannot be resolved to a file nor a directory" do
      expect(@script).to receive(:abort)
      @script.entries("pattern")
    end
  end
end

RSpec.describe MSpecScript, "#files" do
  before :each do
    @script = MSpecScript.new
  end

  it "accumulates the values returned by #entries" do
    expect(@script).to receive(:entries).and_return(["file1"], ["file2"])
    expect(@script.files(["a", "b"])).to eq(["file1", "file2"])
  end

  it "strips a leading '^' and removes the values returned by #entries" do
    expect(@script).to receive(:entries).and_return(["file1"], ["file2"], ["file1"])
    expect(@script.files(["a", "b", "^a"])).to eq(["file2"])
  end

  it "processes the array elements in order" do
    expect(@script).to receive(:entries).and_return(["file1"], ["file1"], ["file2"])
    expect(@script.files(["^a", "a", "b"])).to eq(["file1", "file2"])
  end
end

RSpec.describe MSpecScript, "#files" do
  before :each do
    MSpecScript.set :files, ["file1", "file2"]

    @script = MSpecScript.new
  end

  after :each do
    MSpecScript.config.delete :files
  end

  it "looks up items with leading ':' in the config object" do
    expect(@script).to receive(:entries).and_return(["file1"], ["file2"])
    expect(@script.files([":files"])).to eq(["file1", "file2"])
  end

  it "aborts if the config key is not set" do
    expect(@script).to receive(:abort).with("Key :all_files not found in mspec config.")
    @script.files([":all_files"])
  end
end

RSpec.describe MSpecScript, "#setup_env" do
  before :each do
    @script = MSpecScript.new
    @options, @config = new_option
    allow(@script).to receive(:config).and_return(@config)
  end

  after :each do
  end

  it "sets MSPEC_RUNNER = '1' in the environment" do
    ENV["MSPEC_RUNNER"] = "0"
    @script.setup_env
    expect(ENV["MSPEC_RUNNER"]).to eq("1")
  end

  it "sets RUBY_EXE = config[:target] in the environment" do
    ENV["RUBY_EXE"] = nil
    @script.setup_env
    expect(ENV["RUBY_EXE"]).to eq(@config[:target])
  end

  it "sets RUBY_FLAGS = config[:flags] in the environment" do
    ENV["RUBY_FLAGS"] = nil
    @config[:flags] = ["-w", "-Q"]
    @script.setup_env
    expect(ENV["RUBY_FLAGS"]).to eq("-w -Q")
  end
end
