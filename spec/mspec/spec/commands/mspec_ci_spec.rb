require 'spec_helper'
require 'mspec/runner/mspec'
require 'mspec/runner/filters/tag'
require 'mspec/commands/mspec-ci'

RSpec.describe MSpecCI, "#options" do
  before :each do
    @options, @config = new_option
    allow(MSpecOptions).to receive(:new).and_return(@options)

    @script = MSpecCI.new
    allow(@script).to receive(:config).and_return(@config)
    allow(@script).to receive(:files).and_return([])
  end

  it "enables the chdir option" do
    expect(@options).to receive(:chdir)
    @script.options []
  end

  it "enables the prefix option" do
    expect(@options).to receive(:prefix)
    @script.options []
  end

  it "enables the config option" do
    expect(@options).to receive(:configure)
    @script.options []
  end

  it "provides a custom action (block) to the config option" do
    expect(@script).to receive(:load).with("cfg.mspec")
    @script.options ["-B", "cfg.mspec"]
  end

  it "enables the dry run option" do
    expect(@options).to receive(:pretend)
    @script.options []
  end

  it "enables the unguarded option" do
    expect(@options).to receive(:unguarded)
    @script.options []
  end

  it "enables the interrupt single specs option" do
    expect(@options).to receive(:interrupt)
    @script.options []
  end

  it "enables the formatter options" do
    expect(@options).to receive(:formatters)
    @script.options []
  end

  it "enables the verbose option" do
    expect(@options).to receive(:verbose)
    @script.options []
  end

  it "enables the action options" do
    expect(@options).to receive(:actions)
    @script.options []
  end

  it "enables the action filter options" do
    expect(@options).to receive(:action_filters)
    @script.options []
  end

  it "enables the version option" do
    expect(@options).to receive(:version)
    @script.options []
  end

  it "enables the help option" do
    expect(@options).to receive(:help)
    @script.options []
  end

  it "calls #custom_options" do
    expect(@script).to receive(:custom_options).with(@options)
    @script.options []
  end
end

RSpec.describe MSpecCI, "#run" do
  before :each do
    allow(MSpec).to receive(:process)

    @filter = double("TagFilter")
    allow(TagFilter).to receive(:new).and_return(@filter)
    allow(@filter).to receive(:register)

    @tags = ["fails", "critical", "unstable", "incomplete", "unsupported"]

    @config = { :ci_files => ["one", "two"] }
    @script = MSpecCI.new
    allow(@script).to receive(:exit)
    allow(@script).to receive(:config).and_return(@config)
    allow(@script).to receive(:files).and_return(["one", "two"])
    @script.options []
  end

  it "registers the tags patterns" do
    @config[:tags_patterns] = [/spec/, "tags"]
    expect(MSpec).to receive(:register_tags_patterns).with([/spec/, "tags"])
    @script.run
  end

  it "registers the files to process" do
    expect(MSpec).to receive(:register_files).with(["one", "two"])
    @script.run
  end

  it "registers a tag filter for 'fails', 'unstable', 'incomplete', 'critical', 'unsupported'" do
    filter = double("fails filter")
    expect(TagFilter).to receive(:new).with(:exclude, *@tags).and_return(filter)
    expect(filter).to receive(:register)
    @script.run
  end

  it "registers an additional exclude tag specified by :ci_xtags" do
    @config[:ci_xtags] = "windows"
    filter = double("fails filter")
    expect(TagFilter).to receive(:new).with(:exclude, *(@tags + ["windows"])).and_return(filter)
    expect(filter).to receive(:register)
    @script.run
  end

  it "registers additional exclude tags specified by a :ci_xtags array" do
    @config[:ci_xtags] = ["windows", "windoze"]
    filter = double("fails filter")
    expect(TagFilter).to receive(:new).with(:exclude,
        *(@tags + ["windows", "windoze"])).and_return(filter)
    expect(filter).to receive(:register)
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
