require 'spec_helper'
require 'mspec/runner/mspec'
require 'mspec/commands/mspec-tag'
require 'mspec/runner/actions/tag'
require 'mspec/runner/actions/taglist'
require 'mspec/runner/actions/tagpurge'

one_spec = File.expand_path(File.dirname(__FILE__)) + '/fixtures/one_spec.rb'
two_spec = File.expand_path(File.dirname(__FILE__)) + '/fixtures/two_spec.rb'

RSpec.describe MSpecTag, ".new" do
  before :each do
    @script = MSpecTag.new
  end

  it "sets config[:ltags] to an empty list" do
    expect(@script.config[:ltags]).to eq([])
  end

  it "sets config[:tagger] to :add" do
    @script.config[:tagger] = :add
  end

  it "sets config[:tag] to 'fails:'" do
    @script.config[:tag] = 'fails:'
  end

  it "sets config[:outcome] to :fail" do
    @script.config[:outcome] = :fail
  end
end

RSpec.describe MSpecTag, "#options" do
  before :each do
    @stdout, $stdout = $stdout, IOStub.new

    @argv = [one_spec, two_spec]
    @options, @config = new_option
    allow(MSpecOptions).to receive(:new).and_return(@options)

    @script = MSpecTag.new
    allow(@script).to receive(:config).and_return(@config)
  end

  after :each do
    $stdout = @stdout
  end

  it "enables the filter options" do
    expect(@options).to receive(:filters)
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

  it "enables the version option" do
    expect(@options).to receive(:version)
    @script.options @argv
  end

  it "enables the help option" do
    expect(@options).to receive(:help)
    @script.options @argv
  end

  it "calls #custom_options" do
    expect(@script).to receive(:custom_options).with(@options)
    @script.options @argv
  end

  it "exits if there are no files to process" do
    expect(@options).to receive(:parse).and_return([])
    expect(@script).to receive(:exit)
    @script.options
    expect($stdout.to_s).to include "No files specified"
  end
end

RSpec.describe MSpecTag, "options" do
  before :each do
    @options, @config = new_option
    allow(MSpecOptions).to receive(:new).and_return(@options)
    @script = MSpecTag.new
    allow(@script).to receive(:config).and_return(@config)
  end

  describe "-N, --add TAG" do
    it "is enabled with #options" do
      allow(@options).to receive(:on)
      expect(@options).to receive(:on).with("-N", "--add", "TAG", an_instance_of(String))
      @script.options [one_spec]
    end

    it "sets the mode to :add and sets the tag to TAG" do
      ["-N", "--add"].each do |opt|
        @config[:tagger] = nil
        @config[:tag] = nil
        @script.options [opt, "taggit", one_spec]
        expect(@config[:tagger]).to eq(:add)
        expect(@config[:tag]).to eq("taggit:")
      end
    end
  end

  describe "-R, --del TAG" do
    it "is enabled with #options" do
      allow(@options).to receive(:on)
      expect(@options).to receive(:on).with("-R", "--del", "TAG",
          an_instance_of(String))
      @script.options [one_spec]
    end

    it "it sets the mode to :del, the tag to TAG, and the outcome to :pass" do
      ["-R", "--del"].each do |opt|
        @config[:tagger] = nil
        @config[:tag] = nil
        @config[:outcome] = nil
        @script.options [opt, "taggit", one_spec]
        expect(@config[:tagger]).to eq(:del)
        expect(@config[:tag]).to eq("taggit:")
        expect(@config[:outcome]).to eq(:pass)
      end
    end
  end

  describe "-Q, --pass" do
    it "is enabled with #options" do
      allow(@options).to receive(:on)
      expect(@options).to receive(:on).with("-Q", "--pass", an_instance_of(String))
      @script.options [one_spec]
    end

    it "sets the outcome to :pass" do
      ["-Q", "--pass"].each do |opt|
        @config[:outcome] = nil
        @script.options [opt, one_spec]
        expect(@config[:outcome]).to eq(:pass)
      end
    end
  end

  describe "-F, --fail" do
    it "is enabled with #options" do
      allow(@options).to receive(:on)
      expect(@options).to receive(:on).with("-F", "--fail", an_instance_of(String))
      @script.options [one_spec]
    end

    it "sets the outcome to :fail" do
      ["-F", "--fail"].each do |opt|
        @config[:outcome] = nil
        @script.options [opt, one_spec]
        expect(@config[:outcome]).to eq(:fail)
      end
    end
  end

  describe "-L, --all" do
    it "is enabled with #options" do
      allow(@options).to receive(:on)
      expect(@options).to receive(:on).with("-L", "--all", an_instance_of(String))
      @script.options [one_spec]
    end

    it "sets the outcome to :all" do
      ["-L", "--all"].each do |opt|
        @config[:outcome] = nil
        @script.options [opt, one_spec]
        expect(@config[:outcome]).to eq(:all)
      end
    end
  end

  describe "--list TAG" do
    it "is enabled with #options" do
      allow(@options).to receive(:on)
      expect(@options).to receive(:on).with("--list", "TAG", an_instance_of(String))
      @script.options [one_spec]
    end

    it "sets the mode to :list" do
      @config[:tagger] = nil
      @script.options ["--list", "TAG", one_spec]
      expect(@config[:tagger]).to eq(:list)
    end

    it "sets ltags to include TAG" do
      @config[:tag] = nil
      @script.options ["--list", "TAG", one_spec]
      expect(@config[:ltags]).to eq(["TAG"])
    end
  end

  describe "--list-all" do
    it "is enabled with #options" do
      allow(@options).to receive(:on)
      expect(@options).to receive(:on).with("--list-all", an_instance_of(String))
      @script.options [one_spec]
    end

    it "sets the mode to :list_all" do
      @config[:tagger] = nil
      @script.options ["--list-all", one_spec]
      expect(@config[:tagger]).to eq(:list_all)
    end
  end

  describe "--purge" do
    it "is enabled with #options" do
      allow(@options).to receive(:on)
      expect(@options).to receive(:on).with("--purge", an_instance_of(String))
      @script.options [one_spec]
    end

    it "sets the mode to :purge" do
      @config[:tagger] = nil
      @script.options ["--purge", one_spec]
      expect(@config[:tagger]).to eq(:purge)
    end
  end
end

RSpec.describe MSpecTag, "#run" do
  before :each do
    allow(MSpec).to receive(:process)

    options = double("MSpecOptions").as_null_object
    allow(options).to receive(:parse).and_return(["one", "two"])
    allow(MSpecOptions).to receive(:new).and_return(options)

    @config = { }
    @script = MSpecTag.new
    allow(@script).to receive(:exit)
    allow(@script).to receive(:config).and_return(@config)
    allow(@script).to receive(:files).and_return(["one", "two"])
    @script.options
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

RSpec.describe MSpecTag, "#register" do
  before :each do
    @script = MSpecTag.new
    @config = @script.config
    @config[:tag] = "fake:"
    @config[:atags] = []
    @config[:astrings] = []
    @config[:ltags] = ["fails", "unstable"]

    allow(@script).to receive(:files).and_return([])
    @script.options "fake"

    @t = double("TagAction")
    allow(@t).to receive(:register)

    @tl = double("TagListAction")
    allow(@tl).to receive(:register)
  end

  it "raises an ArgumentError if no recognized action is given" do
    @config[:tagger] = :totally_whack
    expect { @script.register }.to raise_error(ArgumentError)
  end

  describe "when config[:tagger] is the default (:add)" do
    before :each do
      @config[:formatter] = false
    end

    it "creates a TagAction" do
      expect(TagAction).to receive(:new).and_return(@t)
      @script.register
    end

    it "creates a TagAction if config[:tagger] is :del" do
      @config[:tagger] = :del
      @config[:outcome] = :pass
      expect(TagAction).to receive(:new).with(:del, :pass, "fake", nil, [], []).and_return(@t)
      @script.register
    end

    it "calls #register on the TagAction instance" do
      expect(TagAction).to receive(:new).and_return(@t)
      expect(@t).to receive(:register)
      @script.register
    end
  end

  describe "when config[:tagger] is :list" do
    before :each do
      expect(TagListAction).to receive(:new).with(@config[:ltags]).and_return(@tl)
      @config[:tagger] = :list
    end

    it "creates a TagListAction" do
      expect(@tl).to receive(:register)
      @script.register
    end

    it "registers MSpec pretend mode" do
      expect(MSpec).to receive(:register_mode).with(:pretend)
      @script.register
    end

    it "sets config[:formatter] to false" do
      @script.register
      expect(@config[:formatter]).to be_falsey
    end
  end

  describe "when config[:tagger] is :list_all" do
    before :each do
      expect(TagListAction).to receive(:new).with(nil).and_return(@tl)
      @config[:tagger] = :list_all
    end

    it "creates a TagListAction" do
      expect(@tl).to receive(:register)
      @script.register
    end

    it "registers MSpec pretend mode" do
      expect(MSpec).to receive(:register_mode).with(:pretend)
      @script.register
    end

    it "sets config[:formatter] to false" do
      @script.register
      expect(@config[:formatter]).to be_falsey
    end
  end

  describe "when config[:tagger] is :purge" do
    before :each do
      expect(TagPurgeAction).to receive(:new).and_return(@tl)
      allow(MSpec).to receive(:register_mode)
      @config[:tagger] = :purge
    end

    it "creates a TagPurgeAction" do
      expect(@tl).to receive(:register)
      @script.register
    end

    it "registers MSpec in pretend mode" do
      expect(MSpec).to receive(:register_mode).with(:pretend)
      @script.register
    end

    it "registers MSpec in unguarded mode" do
      expect(MSpec).to receive(:register_mode).with(:unguarded)
      @script.register
    end

    it "sets config[:formatter] to false" do
      @script.register
      expect(@config[:formatter]).to be_falsey
    end
  end
end
