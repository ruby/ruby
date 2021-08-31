require 'spec_helper'
require 'yaml'
require 'mspec/commands/mspec'

RSpec.describe MSpecMain, "#options" do
  before :each do
    @options, @config = new_option
    allow(MSpecOptions).to receive(:new).and_return(@options)

    @script = MSpecMain.new
    allow(@script).to receive(:config).and_return(@config)
    allow(@script).to receive(:load)
  end

  it "enables the configure option" do
    expect(@options).to receive(:configure)
    @script.options
  end

  it "provides a custom action (block) to the config option" do
    @script.options ["-B", "config"]
    expect(@config[:options]).to include("-B", "config")
  end

  it "loads the file specified by the config option" do
    expect(@script).to receive(:load).with("config")
    @script.options ["-B", "config"]
  end

  it "enables the target options" do
    expect(@options).to receive(:targets)
    @script.options
  end

  it "sets config[:options] to all argv entries that are not registered options" do
    @options.on "-X", "--exclude", "ARG", "description"
    @script.options [".", "-G", "fail", "-X", "ARG", "--list", "unstable", "some/file.rb"]
    expect(@config[:options]).to eq([".", "-G", "fail", "--list", "unstable", "some/file.rb"])
  end

  it "calls #custom_options" do
    expect(@script).to receive(:custom_options).with(@options)
    @script.options
  end
end

RSpec.describe MSpecMain, "#run" do
  before :each do
    @options, @config = new_option
    allow(MSpecOptions).to receive(:new).and_return(@options)
    @script = MSpecMain.new
    allow(@script).to receive(:config).and_return(@config)
    allow(@script).to receive(:exec)
    @err = $stderr
    $stderr = IOStub.new
  end

  after :each do
    $stderr = @err
  end

  it "uses exec to invoke the runner script" do
    expect(@script).to receive(:exec).with("ruby", "#{MSPEC_HOME}/bin/mspec-run", close_others: false)
    @script.options []
    @script.run
  end

  it "shows the command line on stderr" do
    expect(@script).to receive(:exec).with("ruby", "#{MSPEC_HOME}/bin/mspec-run", close_others: false)
    @script.options []
    @script.run
    expect($stderr.to_s).to eq("$ ruby #{Dir.pwd}/bin/mspec-run\n")
  end

  it "adds config[:launch] to the exec options" do
    expect(@script).to receive(:exec).with("ruby",
        "-Xlaunch.option", "#{MSPEC_HOME}/bin/mspec-run", close_others: false)
    @config[:launch] << "-Xlaunch.option"
    @script.options []
    @script.run
    expect($stderr.to_s).to eq("$ ruby -Xlaunch.option #{Dir.pwd}/bin/mspec-run\n")
  end

  it "calls #multi_exec if the command is 'ci' and the multi option is passed" do
    expect(@script).to receive(:multi_exec) do |argv|
      expect(argv).to eq(["ruby", "#{MSPEC_HOME}/bin/mspec-ci"])
    end
    @script.options ["ci", "-j"]
    expect do
      @script.run
    end.to raise_error(SystemExit)
  end
end

RSpec.describe "The --warnings option" do
  before :each do
    @options, @config = new_option
    allow(MSpecOptions).to receive(:new).and_return(@options)
    @script = MSpecMain.new
    allow(@script).to receive(:config).and_return(@config)
  end

  it "is enabled by #options" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("--warnings", an_instance_of(String))
    @script.options
  end

  it "sets flags to -w" do
    @config[:flags] = []
    @script.options ["--warnings"]
    expect(@config[:flags]).to include("-w")
  end

  it "set OUTPUT_WARNINGS = '1' in the environment" do
    ENV['OUTPUT_WARNINGS'] = '0'
    @script.options ["--warnings"]
    expect(ENV['OUTPUT_WARNINGS']).to eq('1')
  end
end

RSpec.describe "The -j, --multi option" do
  before :each do
    @options, @config = new_option
    allow(MSpecOptions).to receive(:new).and_return(@options)
    @script = MSpecMain.new
    allow(@script).to receive(:config).and_return(@config)
  end

  it "is enabled by #options" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-j", "--multi", an_instance_of(String))
    @script.options
  end

  it "sets the multiple process option" do
    ["-j", "--multi"].each do |opt|
      @config[:multi] = nil
      @script.options [opt]
      expect(@config[:multi]).to eq(true)
    end
  end
end

RSpec.describe "The -h, --help option" do
  before :each do
    @options, @config = new_option
    allow(MSpecOptions).to receive(:new).and_return(@options)
    @script = MSpecMain.new
    allow(@script).to receive(:config).and_return(@config)
  end

  it "is enabled by #options" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-h", "--help", an_instance_of(String))
    @script.options
  end

  it "passes the option to the subscript" do
    ["-h", "--help"].each do |opt|
      @config[:options] = []
      @script.options ["ci", opt]
      expect(@config[:options].sort).to eq(["-h"])
    end
  end

  it "prints help and exits" do
    expect(@script).to receive(:puts).twice
    expect(@script).to receive(:exit).twice
    ["-h", "--help"].each do |opt|
      @script.options [opt]
    end
  end
end

RSpec.describe "The -v, --version option" do
  before :each do
    @options, @config = new_option
    allow(MSpecOptions).to receive(:new).and_return(@options)
    @script = MSpecMain.new
    allow(@script).to receive(:config).and_return(@config)
  end

  it "is enabled by #options" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-v", "--version", an_instance_of(String))
    @script.options
  end

  it "passes the option to the subscripts" do
    ["-v", "--version"].each do |opt|
      @config[:options] = []
      @script.options ["ci", opt]
      expect(@config[:options].sort).to eq(["-v"])
    end
  end

  it "prints the version and exits if no subscript is invoked" do
    @config[:command] = nil
    allow(File).to receive(:basename).and_return("mspec")
    expect(@script).to receive(:puts).twice.with("mspec #{MSpec::VERSION}")
    expect(@script).to receive(:exit).twice
    ["-v", "--version"].each do |opt|
      @script.options [opt]
    end
  end
end
