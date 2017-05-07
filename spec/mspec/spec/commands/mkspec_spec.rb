require 'spec_helper'
require 'mspec/commands/mkspec'


describe "The -c, --constant CONSTANT option" do
  before :each do
    @options = MSpecOptions.new
    MSpecOptions.stub(:new).and_return(@options)
    @script = MkSpec.new
    @config = @script.config
  end

  it "is enabled by #options" do
    @options.stub(:on)
    @options.should_receive(:on).with("-c", "--constant", "CONSTANT",
      an_instance_of(String))
    @script.options []
  end

  it "adds CONSTANT to the list of constants" do
    ["-c", "--constant"].each do |opt|
      @config[:constants] = []
      @script.options [opt, "Object"]
      @config[:constants].should include("Object")
    end
  end
end

describe "The -b, --base DIR option" do
  before :each do
    @options = MSpecOptions.new
    MSpecOptions.stub(:new).and_return(@options)
    @script = MkSpec.new
    @config = @script.config
  end

  it "is enabled by #options" do
    @options.stub(:on)
    @options.should_receive(:on).with("-b", "--base", "DIR",
      an_instance_of(String))
    @script.options
  end

  it "sets the base directory relative to which the spec directories are created" do
    ["-b", "--base"].each do |opt|
      @config[:base] = nil
      @script.options [opt, "superspec"]
      @config[:base].should == File.expand_path("superspec")
    end
  end
end

describe "The -r, --require LIBRARY option" do
  before :each do
    @options = MSpecOptions.new
    MSpecOptions.stub(:new).and_return(@options)
    @script = MkSpec.new
    @config = @script.config
  end

  it "is enabled by #options" do
    @options.stub(:on)
    @options.should_receive(:on).with("-r", "--require", "LIBRARY",
      an_instance_of(String))
    @script.options
  end

  it "adds CONSTANT to the list of constants" do
    ["-r", "--require"].each do |opt|
      @config[:requires] = []
      @script.options [opt, "libspec"]
      @config[:requires].should include("libspec")
    end
  end
end

describe "The -V, --version-guard VERSION option" do
  before :each do
    @options = MSpecOptions.new
    MSpecOptions.stub(:new).and_return(@options)
    @script = MkSpec.new
    @config = @script.config
  end

  it "is enabled by #options" do
    @options.stub(:on)
    @options.should_receive(:on).with("-V", "--version-guard", "VERSION",
      an_instance_of(String))
    @script.options
  end

  it "sets the version for the ruby_version_is guards to VERSION" do
    ["-r", "--require"].each do |opt|
      @config[:requires] = []
      @script.options [opt, "libspec"]
      @config[:requires].should include("libspec")
    end
  end
end

describe MkSpec, "#options" do
  before :each do
    @options = MSpecOptions.new
    MSpecOptions.stub(:new).and_return(@options)
    @script = MkSpec.new
  end

  it "parses the command line options" do
    @options.should_receive(:parse).with(["--this", "and", "--that"])
    @script.options ["--this", "and", "--that"]
  end

  it "parses ARGV unless passed other options" do
    @options.should_receive(:parse).with(ARGV)
    @script.options
  end

  it "prints help and exits if passed an unrecognized option" do
    @options.should_receive(:raise).with(MSpecOptions::ParseError, an_instance_of(String))
    @options.stub(:puts)
    @options.stub(:exit)
    @script.options "--iunknown"
  end
end

describe MkSpec, "#create_directory" do
  before :each do
    @script = MkSpec.new
    @script.config[:base] = "spec"
  end

  it "prints a warning if a file with the directory name exists" do
    File.should_receive(:exist?).and_return(true)
    File.should_receive(:directory?).and_return(false)
    FileUtils.should_not_receive(:mkdir_p)
    @script.should_receive(:puts).with("spec/class already exists and is not a directory.")
    @script.create_directory("Class").should == nil
  end

  it "does nothing if the directory already exists" do
    File.should_receive(:exist?).and_return(true)
    File.should_receive(:directory?).and_return(true)
    FileUtils.should_not_receive(:mkdir_p)
    @script.create_directory("Class").should == "spec/class"
  end

  it "creates the directory if it does not exist" do
    File.should_receive(:exist?).and_return(false)
    @script.should_receive(:mkdir_p).with("spec/class")
    @script.create_directory("Class").should == "spec/class"
  end

  it "creates the directory for a namespaced module if it does not exist" do
    File.should_receive(:exist?).and_return(false)
    @script.should_receive(:mkdir_p).with("spec/struct/tms")
    @script.create_directory("Struct::Tms").should == "spec/struct/tms"
  end
end

describe MkSpec, "#write_requires" do
  before :each do
    @script = MkSpec.new
    @script.config[:base] = "spec"

    @file = double("file")
    File.stub(:open).and_yield(@file)
  end

  it "writes the spec_helper require line" do
    @file.should_receive(:puts).with("require File.expand_path('../../../../spec_helper', __FILE__)")
    @script.write_requires("spec/core/tcejbo", "spec/core/tcejbo/inspect_spec.rb")
  end

  it "writes require lines for each library specified on the command line" do
    @file.stub(:puts)
    @file.should_receive(:puts).with("require File.expand_path('../../../../spec_helper', __FILE__)")
    @file.should_receive(:puts).with("require 'complex'")
    @script.config[:requires] << 'complex'
    @script.write_requires("spec/core/tcejbo", "spec/core/tcejbo/inspect_spec.rb")
  end
end

describe MkSpec, "#write_spec" do
  before :each do
    @file = IOStub.new
    File.stub(:open).and_yield(@file)

    @script = MkSpec.new
    @script.stub(:puts)

    @response = double("system command response")
    @response.stub(:include?).and_return(false)
    @script.stub(:`).and_return(@response)
  end

  it "checks if specs exist for the method if the spec file exists" do
    name = Regexp.escape(@script.ruby)
    @script.should_receive(:`).with(
        %r"#{name} #{MSPEC_HOME}/bin/mspec-run --dry-run --unguarded -fs -e 'Object#inspect' spec/core/tcejbo/inspect_spec.rb")
    @script.write_spec("spec/core/tcejbo/inspect_spec.rb", "Object#inspect", true)
  end

  it "checks for the method name in the spec file output" do
    @response.should_receive(:include?).with("Array#[]=")
    @script.write_spec("spec/core/yarra/element_set_spec.rb", "Array#[]=", true)
  end

  it "returns nil if the spec file exists and contains a spec for the method" do
    @response.stub(:include?).and_return(true)
    @script.write_spec("spec/core/tcejbo/inspect_spec.rb", "Object#inspect", true).should == nil
  end

  it "does not print the spec file name if it exists and contains a spec for the method" do
    @response.stub(:include?).and_return(true)
    @script.should_not_receive(:puts)
    @script.write_spec("spec/core/tcejbo/inspect_spec.rb", "Object#inspect", true)
  end

  it "prints the spec file name if a template spec is written" do
    @script.should_receive(:puts).with("spec/core/tcejbo/inspect_spec.rb")
    @script.write_spec("spec/core/tcejbo/inspect_spec.rb", "Object#inspect", true)
  end

  it "writes a template spec to the file if the spec file does not exist" do
    @file.should_receive(:puts).twice
    @script.should_receive(:puts).with("spec/core/tcejbo/inspect_spec.rb")
    @script.write_spec("spec/core/tcejbo/inspect_spec.rb", "Object#inspect", false)
  end

  it "writes a template spec to the file if it exists but contains no spec for the method" do
    @response.should_receive(:include?).and_return(false)
    @file.should_receive(:puts).twice
    @script.should_receive(:puts).with("spec/core/tcejbo/inspect_spec.rb")
    @script.write_spec("spec/core/tcejbo/inspect_spec.rb", "Object#inspect", true)
  end

  it "writes a template spec" do
    @script.write_spec("spec/core/tcejbo/inspect_spec.rb", "Object#inspect", true)
    @file.should == <<EOS

describe "Object#inspect" do
  it "needs to be reviewed for spec completeness"
end
EOS
  end

  it "writes a template spec with version guard" do
    @script.config[:version] = '""..."1.9"'
    @script.write_spec("spec/core/tcejbo/inspect_spec.rb", "Object#inspect", true)
    @file.should == <<EOS

ruby_version_is ""..."1.9" do
  describe "Object#inspect" do
    it "needs to be reviewed for spec completeness"
  end
end
EOS

  end
end

describe MkSpec, "#create_file" do
  before :each do
    @script = MkSpec.new
    @script.stub(:write_requires)
    @script.stub(:write_spec)

    File.stub(:exist?).and_return(false)
  end

  it "generates a file name based on the directory, class/module, and method" do
    File.should_receive(:join).with("spec/tcejbo", "inspect_spec.rb"
        ).and_return("spec/tcejbo/inspect_spec.rb")
    @script.create_file("spec/tcejbo", "Object", "inspect", "Object#inspect")
  end

  it "does not call #write_requires if the spec file already exists" do
    File.should_receive(:exist?).and_return(true)
    @script.should_not_receive(:write_requires)
    @script.create_file("spec/tcejbo", "Object", "inspect", "Object#inspect")
  end

  it "calls #write_requires if the spec file does not exist" do
    File.should_receive(:exist?).and_return(false)
    @script.should_receive(:write_requires).with(
        "spec/tcejbo", "spec/tcejbo/inspect_spec.rb")
    @script.create_file("spec/tcejbo", "Object", "inspect", "Object#inspect")
  end

  it "calls #write_spec with the file, method name" do
    @script.should_receive(:write_spec).with(
        "spec/tcejbo/inspect_spec.rb", "Object#inspect", false)
    @script.create_file("spec/tcejbo", "Object", "inspect", "Object#inspect")
  end
end

describe MkSpec, "#run" do
  before :each do
    @options = MSpecOptions.new
    MSpecOptions.stub(:new).and_return(@options)

    @map = NameMap.new
    NameMap.stub(:new).and_return(@map)

    @script = MkSpec.new
    @script.stub(:create_directory).and_return("spec/mkspec")
    @script.stub(:create_file)
    @script.config[:constants] = [MkSpec]
  end

  it "loads files in the requires list" do
    @script.stub(:require)
    @script.should_receive(:require).with("alib")
    @script.should_receive(:require).with("blib")
    @script.config[:requires] = ["alib", "blib"]
    @script.run
  end

  it "creates a map of constants to methods" do
    @map.should_receive(:map).with({}, @script.config[:constants]).and_return({})
    @script.run
  end

  it "calls #create_directory for each class/module in the map" do
    @script.should_receive(:create_directory).with("MkSpec").twice
    @script.run
  end

  it "calls #create_file for each method on each class/module in the map" do
    @map.should_receive(:map).with({}, @script.config[:constants]
                                  ).and_return({"MkSpec#" => ["run"]})
    @script.should_receive(:create_file).with("spec/mkspec", "MkSpec", "run", "MkSpec#run")
    @script.run
  end
end

describe MkSpec, ".main" do
  before :each do
    @script = double("MkSpec").as_null_object
    MkSpec.stub(:new).and_return(@script)
  end

  it "sets MSPEC_RUNNER = '1' in the environment" do
    ENV["MSPEC_RUNNER"] = "0"
    MkSpec.main
    ENV["MSPEC_RUNNER"].should == "1"
  end

  it "creates an instance of MSpecScript" do
    MkSpec.should_receive(:new).and_return(@script)
    MkSpec.main
  end

  it "calls the #options method on the script" do
    @script.should_receive(:options)
    MkSpec.main
  end

  it "calls the #run method on the script" do
    @script.should_receive(:run)
    MkSpec.main
  end
end
