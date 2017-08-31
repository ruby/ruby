require 'spec_helper'
require 'yaml'
require 'mspec/commands/mspec'

describe MSpecMain, "#options" do
  before :each do
    @options, @config = new_option
    MSpecOptions.stub(:new).and_return(@options)

    @script = MSpecMain.new
    @script.stub(:config).and_return(@config)
    @script.stub(:load)
  end

  it "enables the configure option" do
    @options.should_receive(:configure)
    @script.options
  end

  it "provides a custom action (block) to the config option" do
    @script.options ["-B", "config"]
    @config[:options].should include("-B", "config")
  end

  it "loads the file specified by the config option" do
    @script.should_receive(:load).with("config")
    @script.options ["-B", "config"]
  end

  it "enables the target options" do
    @options.should_receive(:targets)
    @script.options
  end

  it "sets config[:options] to all argv entries that are not registered options" do
    @options.on "-X", "--exclude", "ARG", "description"
    @script.options [".", "-G", "fail", "-X", "ARG", "--list", "unstable", "some/file.rb"]
    @config[:options].should == [".", "-G", "fail", "--list", "unstable", "some/file.rb"]
  end

  it "calls #custom_options" do
    @script.should_receive(:custom_options).with(@options)
    @script.options
  end
end

describe MSpecMain, "#run" do
  before :each do
    @options, @config = new_option
    MSpecOptions.stub(:new).and_return(@options)
    @script = MSpecMain.new
    @script.stub(:config).and_return(@config)
    @script.stub(:exec)
    @err = $stderr
    $stderr = IOStub.new
  end

  after :each do
    $stderr = @err
  end

  it "uses exec to invoke the runner script" do
    @script.should_receive(:exec).with("ruby", "#{MSPEC_HOME}/bin/mspec-run", close_others: false)
    @script.options []
    @script.run
  end

  it "shows the command line on stderr" do
    @script.should_receive(:exec).with("ruby", "#{MSPEC_HOME}/bin/mspec-run", close_others: false)
    @script.options []
    @script.run
    $stderr.to_s.should == "$ ruby #{Dir.pwd}/bin/mspec-run\n"
  end

  it "adds config[:launch] to the exec options" do
    @script.should_receive(:exec).with("ruby",
        "-Xlaunch.option", "#{MSPEC_HOME}/bin/mspec-run", close_others: false)
    @config[:launch] << "-Xlaunch.option"
    @script.options []
    @script.run
    $stderr.to_s.should == "$ ruby -Xlaunch.option #{Dir.pwd}/bin/mspec-run\n"
  end

  it "calls #multi_exec if the command is 'ci' and the multi option is passed" do
    @script.should_receive(:multi_exec).and_return do |argv|
      argv.should == ["ruby", "#{MSPEC_HOME}/bin/mspec-ci"]
    end
    @script.options ["ci", "-j"]
    lambda do
      @script.run
    end.should raise_error(SystemExit)
  end
end

describe "The --warnings option" do
  before :each do
    @options, @config = new_option
    MSpecOptions.stub(:new).and_return(@options)
    @script = MSpecMain.new
    @script.stub(:config).and_return(@config)
  end

  it "is enabled by #options" do
    @options.stub(:on)
    @options.should_receive(:on).with("--warnings", an_instance_of(String))
    @script.options
  end

  it "sets flags to -w" do
    @config[:flags] = []
    @script.options ["--warnings"]
    @config[:flags].should include("-w")
  end

  it "set OUTPUT_WARNINGS = '1' in the environment" do
    ENV['OUTPUT_WARNINGS'] = '0'
    @script.options ["--warnings"]
    ENV['OUTPUT_WARNINGS'].should == '1'
  end
end

describe "The -j, --multi option" do
  before :each do
    @options, @config = new_option
    MSpecOptions.stub(:new).and_return(@options)
    @script = MSpecMain.new
    @script.stub(:config).and_return(@config)
  end

  it "is enabled by #options" do
    @options.stub(:on)
    @options.should_receive(:on).with("-j", "--multi", an_instance_of(String))
    @script.options
  end

  it "sets the multiple process option" do
    ["-j", "--multi"].each do |opt|
      @config[:multi] = nil
      @script.options [opt]
      @config[:multi].should == true
    end
  end
end

describe "The -h, --help option" do
  before :each do
    @options, @config = new_option
    MSpecOptions.stub(:new).and_return(@options)
    @script = MSpecMain.new
    @script.stub(:config).and_return(@config)
  end

  it "is enabled by #options" do
    @options.stub(:on)
    @options.should_receive(:on).with("-h", "--help", an_instance_of(String))
    @script.options
  end

  it "passes the option to the subscript" do
    ["-h", "--help"].each do |opt|
      @config[:options] = []
      @script.options ["ci", opt]
      @config[:options].sort.should == ["-h"]
    end
  end

  it "prints help and exits" do
    @script.should_receive(:puts).twice
    @script.should_receive(:exit).twice
    ["-h", "--help"].each do |opt|
      @script.options [opt]
    end
  end
end

describe "The -v, --version option" do
  before :each do
    @options, @config = new_option
    MSpecOptions.stub(:new).and_return(@options)
    @script = MSpecMain.new
    @script.stub(:config).and_return(@config)
  end

  it "is enabled by #options" do
    @options.stub(:on)
    @options.should_receive(:on).with("-v", "--version", an_instance_of(String))
    @script.options
  end

  it "passes the option to the subscripts" do
    ["-v", "--version"].each do |opt|
      @config[:options] = []
      @script.options ["ci", opt]
      @config[:options].sort.should == ["-v"]
    end
  end

  it "prints the version and exits if no subscript is invoked" do
    @config[:command] = nil
    File.stub(:basename).and_return("mspec")
    @script.should_receive(:puts).twice.with("mspec #{MSpec::VERSION}")
    @script.should_receive(:exit).twice
    ["-v", "--version"].each do |opt|
      @script.options [opt]
    end
  end
end
