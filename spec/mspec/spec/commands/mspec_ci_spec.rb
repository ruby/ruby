require 'spec_helper'
require 'mspec/runner/mspec'
require 'mspec/runner/filters/tag'
require 'mspec/commands/mspec-ci'

describe MSpecCI, "#options" do
  before :each do
    @options, @config = new_option
    MSpecOptions.stub(:new).and_return(@options)

    @script = MSpecCI.new
    @script.stub(:config).and_return(@config)
    @script.stub(:files).and_return([])
  end

  it "enables the chdir option" do
    @options.should_receive(:chdir)
    @script.options
  end

  it "enables the prefix option" do
    @options.should_receive(:prefix)
    @script.options
  end

  it "enables the config option" do
    @options.should_receive(:configure)
    @script.options
  end

  it "provides a custom action (block) to the config option" do
    @script.should_receive(:load).with("cfg.mspec")
    @script.options ["-B", "cfg.mspec"]
  end

  it "enables the name option" do
    @options.should_receive(:name)
    @script.options
  end

  it "enables the dry run option" do
    @options.should_receive(:pretend)
    @script.options
  end

  it "enables the unguarded option" do
    @options.should_receive(:unguarded)
    @script.options
  end

  it "enables the interrupt single specs option" do
    @options.should_receive(:interrupt)
    @script.options
  end

  it "enables the formatter options" do
    @options.should_receive(:formatters)
    @script.options
  end

  it "enables the verbose option" do
    @options.should_receive(:verbose)
    @script.options
  end

  it "enables the action options" do
    @options.should_receive(:actions)
    @script.options
  end

  it "enables the action filter options" do
    @options.should_receive(:action_filters)
    @script.options
  end

  it "enables the version option" do
    @options.should_receive(:version)
    @script.options
  end

  it "enables the help option" do
    @options.should_receive(:help)
    @script.options
  end

  it "calls #custom_options" do
    @script.should_receive(:custom_options).with(@options)
    @script.options
  end
end

describe MSpecCI, "#run" do
  before :each do
    MSpec.stub(:process)

    @filter = double("TagFilter")
    TagFilter.stub(:new).and_return(@filter)
    @filter.stub(:register)

    @tags = ["fails", "critical", "unstable", "incomplete", "unsupported"]

    @config = { :ci_files => ["one", "two"] }
    @script = MSpecCI.new
    @script.stub(:exit)
    @script.stub(:config).and_return(@config)
    @script.stub(:files).and_return(["one", "two"])
    @script.options
  end

  it "registers the tags patterns" do
    @config[:tags_patterns] = [/spec/, "tags"]
    MSpec.should_receive(:register_tags_patterns).with([/spec/, "tags"])
    @script.run
  end

  it "registers the files to process" do
    MSpec.should_receive(:register_files).with(["one", "two"])
    @script.run
  end

  it "registers a tag filter for 'fails', 'unstable', 'incomplete', 'critical', 'unsupported'" do
    filter = double("fails filter")
    TagFilter.should_receive(:new).with(:exclude, *@tags).and_return(filter)
    filter.should_receive(:register)
    @script.run
  end

  it "registers an additional exclude tag specified by :ci_xtags" do
    @config[:ci_xtags] = "windows"
    filter = double("fails filter")
    TagFilter.should_receive(:new).with(:exclude, *(@tags + ["windows"])).and_return(filter)
    filter.should_receive(:register)
    @script.run
  end

  it "registers additional exclude tags specified by a :ci_xtags array" do
    @config[:ci_xtags] = ["windows", "windoze"]
    filter = double("fails filter")
    TagFilter.should_receive(:new).with(:exclude,
        *(@tags + ["windows", "windoze"])).and_return(filter)
    filter.should_receive(:register)
    @script.run
  end

  it "processes the files" do
    MSpec.should_receive(:process)
    @script.run
  end

  it "exits with the exit code registered with MSpec" do
    MSpec.stub(:exit_code).and_return(7)
    @script.should_receive(:exit).with(7)
    @script.run
  end
end
