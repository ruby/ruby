require 'spec_helper'
require 'mspec/runner/mspec'
require 'mspec/commands/mspec-run'

one_spec = File.expand_path(File.dirname(__FILE__)) + '/fixtures/one_spec.rb'
two_spec = File.expand_path(File.dirname(__FILE__)) + '/fixtures/two_spec.rb'

RSpec.describe MSpecRun, ".new" do
  before :each do
    @script = MSpecRun.new
  end

  it "sets config[:files] to an empty list" do
    expect(@script.config[:files]).to eq([])
  end
end

RSpec.describe MSpecRun, "#options" do
  before :each do
    @argv = [one_spec, two_spec]
    @options, @config = new_option
    allow(MSpecOptions).to receive(:new).and_return(@options)

    @script = MSpecRun.new
    allow(@script).to receive(:config).and_return(@config)
  end

  it "enables the filter options" do
    expect(@options).to receive(:filters)
    @script.options @argv
  end

  it "enables the chdir option" do
    expect(@options).to receive(:chdir)
    @script.options @argv
  end

  it "enables the prefix option" do
    expect(@options).to receive(:prefix)
    @script.options @argv
  end

  it "enables the configure option" do
    expect(@options).to receive(:configure)
    @script.options @argv
  end

  it "provides a custom action (block) to the config option" do
    expect(@script).to receive(:load).with("cfg.mspec")
    @script.options ["-B", "cfg.mspec", one_spec]
  end

  it "enables the randomize option to runs specs in random order" do
    expect(@options).to receive(:randomize)
    @script.options @argv
  end

  it "enables the dry run option" do
    expect(@options).to receive(:pretend)
    @script.options @argv
  end

  it "enables the unguarded option" do
    expect(@options).to receive(:unguarded)
    @script.options @argv
  end

  it "enables the interrupt single specs option" do
    expect(@options).to receive(:interrupt)
    @script.options @argv
  end

  it "enables the formatter options" do
    expect(@options).to receive(:formatters)
    @script.options @argv
  end

  it "enables the verbose option" do
    expect(@options).to receive(:verbose)
    @script.options @argv
  end

  it "enables the verify options" do
    expect(@options).to receive(:verify)
    @script.options @argv
  end

  it "enables the action options" do
    expect(@options).to receive(:actions)
    @script.options @argv
  end

  it "enables the action filter options" do
    expect(@options).to receive(:action_filters)
    @script.options @argv
  end

  it "enables the version option" do
    expect(@options).to receive(:version)
    @script.options @argv
  end

  it "enables the help option" do
    expect(@options).to receive(:help)
    @script.options @argv
  end

  it "exits if there are no files to process and './spec' is not a directory" do
    expect(File).to receive(:directory?).with("./spec").and_return(false)
    expect(@options).to receive(:parse).and_return([])
    expect(@script).to receive(:abort).with("No files specified.")
    @script.options
  end

  it "process 'spec/' if it is a directory and no files were specified" do
    expect(File).to receive(:directory?).with("./spec").and_return(true)
    expect(@options).to receive(:parse).and_return([])
    expect(@script).to receive(:files).with(["spec/"]).and_return(["spec/a_spec.rb"])
    @script.options
  end

  it "calls #custom_options" do
    expect(@script).to receive(:custom_options).with(@options)
    @script.options @argv
  end
end

RSpec.describe MSpecRun, "#run" do
  before :each do
    @script = MSpecRun.new
    allow(@script).to receive(:exit)
    @spec_dir = File.expand_path(File.dirname(__FILE__)+"/fixtures")
    @file_patterns = [
      @spec_dir+"/level2",
      @spec_dir+"/one_spec.rb",
      @spec_dir+"/two_spec.rb"]
    @files = [
      @spec_dir+"/level2/three_spec.rb",
      @spec_dir+"/one_spec.rb",
      @spec_dir+"/two_spec.rb"]
    @script.options @file_patterns
    allow(MSpec).to receive :process
  end

  it "registers the tags patterns" do
    @script.config[:tags_patterns] = [/spec/, "tags"]
    expect(MSpec).to receive(:register_tags_patterns).with([/spec/, "tags"])
    @script.run
  end

  it "registers the files to process" do
    expect(MSpec).to receive(:register_files).with(@files)
    @script.run
  end

  it "uses config[:files] if no files are given on the command line" do
    @script.config[:files] = @file_patterns
    expect(MSpec).to receive(:register_files).with(@files)
    @script.options []
    @script.run
  end

  it "processes the files" do
    expect(MSpec).to receive(:process)
    @script.run
  end

  it "exits with the exit code registered with MSpec" do
    allow(MSpec).to receive(:exit_code).and_return(7)
    expect(@script).to receive(:exit).with(7)
    @script.run
  end
end
