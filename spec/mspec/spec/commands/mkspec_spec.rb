require 'spec_helper'
require 'mspec/commands/mkspec'
require 'fileutils'

RSpec.describe "The -c, --constant CONSTANT option" do
  before :each do
    @options = MSpecOptions.new
    allow(MSpecOptions).to receive(:new).and_return(@options)
    @script = MkSpec.new
    @config = @script.config
  end

  it "is enabled by #options" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-c", "--constant", "CONSTANT",
      an_instance_of(String))
    @script.options []
  end

  it "adds CONSTANT to the list of constants" do
    ["-c", "--constant"].each do |opt|
      @config[:constants] = []
      @script.options [opt, "Object"]
      expect(@config[:constants]).to include("Object")
    end
  end
end

RSpec.describe "The -b, --base DIR option" do
  before :each do
    @options = MSpecOptions.new
    allow(MSpecOptions).to receive(:new).and_return(@options)
    @script = MkSpec.new
    @config = @script.config
  end

  it "is enabled by #options" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-b", "--base", "DIR",
      an_instance_of(String))
    @script.options []
  end

  it "sets the base directory relative to which the spec directories are created" do
    ["-b", "--base"].each do |opt|
      @config[:base] = nil
      @script.options [opt, "superspec"]
      expect(@config[:base]).to eq(File.expand_path("superspec"))
    end
  end
end

RSpec.describe "The -r, --require LIBRARY option" do
  before :each do
    @options = MSpecOptions.new
    allow(MSpecOptions).to receive(:new).and_return(@options)
    @script = MkSpec.new
    @config = @script.config
  end

  it "is enabled by #options" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-r", "--require", "LIBRARY",
      an_instance_of(String))
    @script.options []
  end

  it "adds CONSTANT to the list of constants" do
    ["-r", "--require"].each do |opt|
      @config[:requires] = []
      @script.options [opt, "libspec"]
      expect(@config[:requires]).to include("libspec")
    end
  end
end

RSpec.describe "The -V, --version-guard VERSION option" do
  before :each do
    @options = MSpecOptions.new
    allow(MSpecOptions).to receive(:new).and_return(@options)
    @script = MkSpec.new
    @config = @script.config
  end

  it "is enabled by #options" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-V", "--version-guard", "VERSION",
      an_instance_of(String))
    @script.options []
  end

  it "sets the version for the ruby_version_is guards to VERSION" do
    ["-r", "--require"].each do |opt|
      @config[:requires] = []
      @script.options [opt, "libspec"]
      expect(@config[:requires]).to include("libspec")
    end
  end
end

RSpec.describe MkSpec, "#options" do
  before :each do
    @options = MSpecOptions.new
    allow(MSpecOptions).to receive(:new).and_return(@options)
    @script = MkSpec.new
  end

  it "parses the command line options" do
    expect(@options).to receive(:parse).with(["--this", "and", "--that"])
    @script.options ["--this", "and", "--that"]
  end

  it "parses ARGV unless passed other options" do
    expect(@options).to receive(:parse).with(ARGV)
    @script.options
  end

  it "prints help and exits if passed an unrecognized option" do
    expect(@options).to receive(:raise).with(MSpecOptions::ParseError, an_instance_of(String))
    allow(@options).to receive(:puts)
    allow(@options).to receive(:exit)
    @script.options ["--iunknown"]
  end
end

RSpec.describe MkSpec, "#create_directory" do
  before :each do
    @script = MkSpec.new
    @script.config[:base] = "spec"
  end

  it "prints a warning if a file with the directory name exists" do
    expect(File).to receive(:exist?).and_return(true)
    expect(File).to receive(:directory?).and_return(false)
    expect(FileUtils).not_to receive(:mkdir_p)
    expect(@script).to receive(:puts).with("spec/class already exists and is not a directory.")
    expect(@script.create_directory("Class")).to eq(nil)
  end

  it "does nothing if the directory already exists" do
    expect(File).to receive(:exist?).and_return(true)
    expect(File).to receive(:directory?).and_return(true)
    expect(FileUtils).not_to receive(:mkdir_p)
    expect(@script.create_directory("Class")).to eq("spec/class")
  end

  it "creates the directory if it does not exist" do
    expect(File).to receive(:exist?).and_return(false)
    expect(@script).to receive(:mkdir_p).with("spec/class")
    expect(@script.create_directory("Class")).to eq("spec/class")
  end

  it "creates the directory for a namespaced module if it does not exist" do
    expect(File).to receive(:exist?).and_return(false)
    expect(@script).to receive(:mkdir_p).with("spec/struct/tms")
    expect(@script.create_directory("Struct::Tms")).to eq("spec/struct/tms")
  end
end

RSpec.describe MkSpec, "#write_requires" do
  before :each do
    @script = MkSpec.new
    @script.config[:base] = "spec"

    @file = double("file")
    allow(File).to receive(:open).and_yield(@file)
  end

  it "writes the spec_helper require line" do
    expect(@file).to receive(:puts).with("require_relative '../../../spec_helper'")
    @script.write_requires("spec/core/tcejbo", "spec/core/tcejbo/inspect_spec.rb")
  end

  it "writes require lines for each library specified on the command line" do
    allow(@file).to receive(:puts)
    expect(@file).to receive(:puts).with("require_relative '../../../spec_helper'")
    expect(@file).to receive(:puts).with("require 'complex'")
    @script.config[:requires] << 'complex'
    @script.write_requires("spec/core/tcejbo", "spec/core/tcejbo/inspect_spec.rb")
  end
end

RSpec.describe MkSpec, "#write_spec" do
  before :each do
    @file = IOStub.new
    allow(File).to receive(:open).and_yield(@file)

    @script = MkSpec.new
    allow(@script).to receive(:puts)

    @response = double("system command response")
    allow(@response).to receive(:include?).and_return(false)
    allow(@script).to receive(:`).and_return(@response)
  end

  it "checks if specs exist for the method if the spec file exists" do
    name = Regexp.escape(RbConfig.ruby)
    expect(@script).to receive(:`).with(
        %r"#{name} #{MSPEC_HOME}/bin/mspec-run --dry-run --unguarded -fs -e 'Object#inspect' spec/core/tcejbo/inspect_spec.rb")
    @script.write_spec("spec/core/tcejbo/inspect_spec.rb", "Object#inspect", true)
  end

  it "checks for the method name in the spec file output" do
    expect(@response).to receive(:include?).with("Array#[]=")
    @script.write_spec("spec/core/yarra/element_set_spec.rb", "Array#[]=", true)
  end

  it "returns nil if the spec file exists and contains a spec for the method" do
    allow(@response).to receive(:include?).and_return(true)
    expect(@script.write_spec("spec/core/tcejbo/inspect_spec.rb", "Object#inspect", true)).to eq(nil)
  end

  it "does not print the spec file name if it exists and contains a spec for the method" do
    allow(@response).to receive(:include?).and_return(true)
    expect(@script).not_to receive(:puts)
    @script.write_spec("spec/core/tcejbo/inspect_spec.rb", "Object#inspect", true)
  end

  it "prints the spec file name if a template spec is written" do
    expect(@script).to receive(:puts).with("spec/core/tcejbo/inspect_spec.rb")
    @script.write_spec("spec/core/tcejbo/inspect_spec.rb", "Object#inspect", true)
  end

  it "writes a template spec to the file if the spec file does not exist" do
    expect(@file).to receive(:puts).twice
    expect(@script).to receive(:puts).with("spec/core/tcejbo/inspect_spec.rb")
    @script.write_spec("spec/core/tcejbo/inspect_spec.rb", "Object#inspect", false)
  end

  it "writes a template spec to the file if it exists but contains no spec for the method" do
    expect(@response).to receive(:include?).and_return(false)
    expect(@file).to receive(:puts).twice
    expect(@script).to receive(:puts).with("spec/core/tcejbo/inspect_spec.rb")
    @script.write_spec("spec/core/tcejbo/inspect_spec.rb", "Object#inspect", true)
  end

  it "writes a template spec" do
    @script.write_spec("spec/core/tcejbo/inspect_spec.rb", "Object#inspect", true)
    expect(@file).to eq <<EOS

describe "Object#inspect" do
  it "needs to be reviewed for spec completeness"
end
EOS
  end

  it "writes a template spec with version guard" do
    @script.config[:version] = '""..."1.9"'
    @script.write_spec("spec/core/tcejbo/inspect_spec.rb", "Object#inspect", true)
    expect(@file).to eq <<EOS

ruby_version_is ""..."1.9" do
  describe "Object#inspect" do
    it "needs to be reviewed for spec completeness"
  end
end
EOS

  end
end

RSpec.describe MkSpec, "#create_file" do
  before :each do
    @script = MkSpec.new
    allow(@script).to receive(:write_requires)
    allow(@script).to receive(:write_spec)

    allow(File).to receive(:exist?).and_return(false)
  end

  it "generates a file name based on the directory, class/module, and method" do
    expect(File).to receive(:join).with("spec/tcejbo", "inspect_spec.rb"
        ).and_return("spec/tcejbo/inspect_spec.rb")
    @script.create_file("spec/tcejbo", "Object", "inspect", "Object#inspect")
  end

  it "does not call #write_requires if the spec file already exists" do
    expect(File).to receive(:exist?).and_return(true)
    expect(@script).not_to receive(:write_requires)
    @script.create_file("spec/tcejbo", "Object", "inspect", "Object#inspect")
  end

  it "calls #write_requires if the spec file does not exist" do
    expect(File).to receive(:exist?).and_return(false)
    expect(@script).to receive(:write_requires).with(
        "spec/tcejbo", "spec/tcejbo/inspect_spec.rb")
    @script.create_file("spec/tcejbo", "Object", "inspect", "Object#inspect")
  end

  it "calls #write_spec with the file, method name" do
    expect(@script).to receive(:write_spec).with(
        "spec/tcejbo/inspect_spec.rb", "Object#inspect", false)
    @script.create_file("spec/tcejbo", "Object", "inspect", "Object#inspect")
  end
end

RSpec.describe MkSpec, "#run" do
  before :each do
    @options = MSpecOptions.new
    allow(MSpecOptions).to receive(:new).and_return(@options)

    @map = NameMap.new
    allow(NameMap).to receive(:new).and_return(@map)

    @script = MkSpec.new
    allow(@script).to receive(:create_directory).and_return("spec/mkspec")
    allow(@script).to receive(:create_file)
    @script.config[:constants] = [MkSpec]
  end

  it "loads files in the requires list" do
    allow(@script).to receive(:require)
    expect(@script).to receive(:require).with("alib")
    expect(@script).to receive(:require).with("blib")
    @script.config[:requires] = ["alib", "blib"]
    @script.run
  end

  it "creates a map of constants to methods" do
    expect(@map).to receive(:map).with({}, @script.config[:constants]).and_return({})
    @script.run
  end

  it "calls #create_directory for each class/module in the map" do
    expect(@script).to receive(:create_directory).with("MkSpec").twice
    @script.run
  end

  it "calls #create_file for each method on each class/module in the map" do
    expect(@map).to receive(:map).with({}, @script.config[:constants]
                                  ).and_return({"MkSpec#" => ["run"]})
    expect(@script).to receive(:create_file).with("spec/mkspec", "MkSpec", "run", "MkSpec#run")
    @script.run
  end
end

RSpec.describe MkSpec, ".main" do
  before :each do
    @script = double("MkSpec").as_null_object
    allow(MkSpec).to receive(:new).and_return(@script)
  end

  it "sets MSPEC_RUNNER = '1' in the environment" do
    ENV["MSPEC_RUNNER"] = "0"
    MkSpec.main
    expect(ENV["MSPEC_RUNNER"]).to eq("1")
  end

  it "creates an instance of MSpecScript" do
    expect(MkSpec).to receive(:new).and_return(@script)
    MkSpec.main
  end

  it "calls the #options method on the script" do
    expect(@script).to receive(:options)
    MkSpec.main
  end

  it "calls the #run method on the script" do
    expect(@script).to receive(:run)
    MkSpec.main
  end
end
