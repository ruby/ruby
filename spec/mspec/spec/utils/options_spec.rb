require 'spec_helper'
require 'mspec/utils/options'
require 'mspec/version'
require 'mspec/guards/guard'
require 'mspec/runner/mspec'
require 'mspec/runner/formatters'

RSpec.describe MSpecOption, ".new" do
  before :each do
    @opt = MSpecOption.new("-a", "--bdc", "ARG", "desc", :block)
  end

  it "sets the short attribute" do
    expect(@opt.short).to eq("-a")
  end

  it "sets the long attribute" do
    expect(@opt.long).to eq("--bdc")
  end

  it "sets the arg attribute" do
    expect(@opt.arg).to eq("ARG")
  end

  it "sets the description attribute" do
    expect(@opt.description).to eq("desc")
  end

  it "sets the block attribute" do
    expect(@opt.block).to eq(:block)
  end
end

RSpec.describe MSpecOption, "#arg?" do
  it "returns true if arg attribute is not nil" do
    expect(MSpecOption.new(nil, nil, "ARG", nil, nil).arg?).to be_truthy
  end

  it "returns false if arg attribute is nil" do
    expect(MSpecOption.new(nil, nil, nil, nil, nil).arg?).to be_falsey
  end
end

RSpec.describe MSpecOption, "#match?" do
  before :each do
    @opt = MSpecOption.new("-a", "--bdc", "ARG", "desc", :block)
  end

  it "returns true if the argument matches the short option" do
    expect(@opt.match?("-a")).to be_truthy
  end

  it "returns true if the argument matches the long option" do
    expect(@opt.match?("--bdc")).to be_truthy
  end

  it "returns false if the argument matches neither the short nor long option" do
    expect(@opt.match?("-b")).to be_falsey
    expect(@opt.match?("-abdc")).to be_falsey
  end
end

RSpec.describe MSpecOptions, ".new" do
  before :each do
    @opt = MSpecOptions.new("cmd", 20, :config)
  end

  it "sets the banner attribute" do
    expect(@opt.banner).to eq("cmd")
  end

  it "sets the config attribute" do
    expect(@opt.config).to eq(:config)
  end

  it "sets the width attribute" do
    expect(@opt.width).to eq(20)
  end

  it "sets the default width attribute" do
    expect(MSpecOptions.new.width).to eq(30)
  end
end

RSpec.describe MSpecOptions, "#on" do
  before :each do
    @opt = MSpecOptions.new
  end

  it "adds a short option" do
    expect(@opt).to receive(:add).with("-a", nil, nil, "desc", nil)
    @opt.on("-a", "desc")
  end

  it "adds a short option taking an argument" do
    expect(@opt).to receive(:add).with("-a", nil, "ARG", "desc", nil)
    @opt.on("-a", "ARG", "desc")
  end

  it "adds a long option" do
    expect(@opt).to receive(:add).with("-a", nil, nil, "desc", nil)
    @opt.on("-a", "desc")
  end

  it "adds a long option taking an argument" do
    expect(@opt).to receive(:add).with("-a", nil, nil, "desc", nil)
    @opt.on("-a", "desc")
  end

  it "adds a short and long option" do
    expect(@opt).to receive(:add).with("-a", nil, nil, "desc", nil)
    @opt.on("-a", "desc")
  end

  it "adds a short and long option taking an argument" do
    expect(@opt).to receive(:add).with("-a", nil, nil, "desc", nil)
    @opt.on("-a", "desc")
  end

  it "raises MSpecOptions::OptionError if pass less than 2 arguments" do
    expect { @opt.on    }.to raise_error(MSpecOptions::OptionError)
    expect { @opt.on "" }.to raise_error(MSpecOptions::OptionError)
  end
end

RSpec.describe MSpecOptions, "#add" do
  before :each do
    @opt = MSpecOptions.new "cmd", 20
    @prc = lambda { }
  end

  it "adds documentation for an option" do
    expect(@opt).to receive(:doc).with("   -t, --typo ARG   Correct typo ARG")
    @opt.add("-t", "--typo", "ARG", "Correct typo ARG", @prc)
  end

  it "leaves spaces in the documentation for a missing short option" do
    expect(@opt).to receive(:doc).with("       --typo ARG   Correct typo ARG")
    @opt.add(nil, "--typo", "ARG", "Correct typo ARG", @prc)
  end

  it "handles a short option with argument but no long argument" do
    expect(@opt).to receive(:doc).with("   -t ARG           Correct typo ARG")
    @opt.add("-t", nil, "ARG", "Correct typo ARG", @prc)
  end

  it "registers an option" do
    option = MSpecOption.new "-t", "--typo", "ARG", "Correct typo ARG", @prc
    expect(MSpecOption).to receive(:new).with(
        "-t", "--typo", "ARG", "Correct typo ARG", @prc).and_return(option)
    @opt.add("-t", "--typo", "ARG", "Correct typo ARG", @prc)
    expect(@opt.options).to eq([option])
  end
end

RSpec.describe MSpecOptions, "#match?" do
  before :each do
    @opt = MSpecOptions.new
  end

  it "returns the MSpecOption instance matching the argument" do
    @opt.on "-a", "--abdc", "desc"
    option = @opt.match? "-a"
    expect(@opt.match?("--abdc")).to be(option)
    expect(option).to be_kind_of(MSpecOption)
    expect(option.short).to eq("-a")
    expect(option.long).to eq("--abdc")
    expect(option.description).to eq("desc")
  end
end

RSpec.describe MSpecOptions, "#process" do
  before :each do
    @opt = MSpecOptions.new
    ScratchPad.clear
  end

  it "calls the on_extra block if the argument does not match any option" do
    @opt.on_extra { ScratchPad.record :extra }
    @opt.process ["-a"], "-a", "-a", nil
    expect(ScratchPad.recorded).to eq(:extra)
  end

  it "returns the matching option" do
    @opt.on "-a", "ARG", "desc"
    option = @opt.process [], "-a", "-a", "ARG"
    expect(option).to be_kind_of(MSpecOption)
    expect(option.short).to eq("-a")
    expect(option.arg).to eq("ARG")
    expect(option.description).to eq("desc")
  end

  it "raises an MSpecOptions::ParseError if arg is nil and there are no more entries in argv" do
    @opt.on "-a", "ARG", "desc"
    expect { @opt.process [], "-a", "-a", nil }.to raise_error(MSpecOptions::ParseError)
  end

  it "fetches the argument for the option from argv if arg is nil" do
    @opt.on("-a", "ARG", "desc") { |o| ScratchPad.record o }
    @opt.process ["ARG"], "-a", "-a", nil
    expect(ScratchPad.recorded).to eq("ARG")
  end

  it "calls the option's block" do
    @opt.on("-a", "ARG", "desc") { ScratchPad.record :option }
    @opt.process [], "-a", "-a", "ARG"
    expect(ScratchPad.recorded).to eq(:option)
  end

  it "does not call the option's block if it is nil" do
    @opt.on "-a", "ARG", "desc"
    expect { @opt.process [], "-a", "-a", "ARG" }.not_to raise_error
  end
end

RSpec.describe MSpecOptions, "#split" do
  before :each do
    @opt = MSpecOptions.new
  end

  it "breaks a string at the nth character" do
    opt, arg, rest = @opt.split "-bdc", 2
    expect(opt).to eq("-b")
    expect(arg).to eq("dc")
    expect(rest).to eq("dc")
  end

  it "returns nil for arg if there are no characters left" do
    opt, arg, rest = @opt.split "-b", 2
    expect(opt).to eq("-b")
    expect(arg).to eq(nil)
    expect(rest).to eq("")
  end
end

RSpec.describe MSpecOptions, "#parse" do
  before :each do
    @opt = MSpecOptions.new
    @prc = lambda { ScratchPad.record :parsed }
    @arg_prc = lambda { |o| ScratchPad.record [:parsed, o] }
    ScratchPad.clear
  end

  it "parses a short option" do
    @opt.on "-a", "desc", &@prc
    @opt.parse ["-a"]
    expect(ScratchPad.recorded).to eq(:parsed)
  end

  it "parse a long option" do
    @opt.on "--abdc", "desc", &@prc
    @opt.parse ["--abdc"]
    expect(ScratchPad.recorded).to eq(:parsed)
  end

  it "parses a short option group" do
    @opt.on "-a", "ARG", "desc", &@arg_prc
    @opt.parse ["-a", "ARG"]
    expect(ScratchPad.recorded).to eq([:parsed, "ARG"])
  end

  it "parses a short option with an argument" do
    @opt.on "-a", "ARG", "desc", &@arg_prc
    @opt.parse ["-a", "ARG"]
    expect(ScratchPad.recorded).to eq([:parsed, "ARG"])
  end

  it "parses a short option with connected argument" do
    @opt.on "-a", "ARG", "desc", &@arg_prc
    @opt.parse ["-aARG"]
    expect(ScratchPad.recorded).to eq([:parsed, "ARG"])
  end

  it "parses a long option with an argument" do
    @opt.on "--abdc", "ARG", "desc", &@arg_prc
    @opt.parse ["--abdc", "ARG"]
    expect(ScratchPad.recorded).to eq([:parsed, "ARG"])
  end

  it "parses a long option with an '=' argument" do
    @opt.on "--abdc", "ARG", "desc", &@arg_prc
    @opt.parse ["--abdc=ARG"]
    expect(ScratchPad.recorded).to eq([:parsed, "ARG"])
  end

  it "parses a short option group with the final option taking an argument" do
    ScratchPad.record []
    @opt.on("-a", "desc") { |o| ScratchPad << :a }
    @opt.on("-b", "ARG", "desc") { |o| ScratchPad << [:b, o] }
    @opt.parse ["-ab", "ARG"]
    expect(ScratchPad.recorded).to eq([:a, [:b, "ARG"]])
  end

  it "parses a short option group with a connected argument" do
    ScratchPad.record []
    @opt.on("-a", "desc") { |o| ScratchPad << :a }
    @opt.on("-b", "ARG", "desc") { |o| ScratchPad << [:b, o] }
    @opt.on("-c", "desc") { |o| ScratchPad << :c }
    @opt.parse ["-acbARG"]
    expect(ScratchPad.recorded).to eq([:a, :c, [:b, "ARG"]])
  end

  it "returns the unprocessed entries" do
    @opt.on "-a", "ARG", "desc", &@arg_prc
    expect(@opt.parse(["abdc", "-a", "ilny"])).to eq(["abdc"])
  end

  it "calls the on_extra handler with unrecognized options" do
    ScratchPad.record []
    @opt.on_extra { |o| ScratchPad << o }
    @opt.on "-a", "desc"
    @opt.parse ["-a", "-b"]
    expect(ScratchPad.recorded).to eq(["-b"])
  end

  it "does not attempt to call the block if it is nil" do
    @opt.on "-a", "ARG", "desc"
    expect(@opt.parse(["-a", "ARG"])).to eq([])
  end

  it "raises MSpecOptions::ParseError if passed an unrecognized option" do
    expect(@opt).to receive(:raise).with(MSpecOptions::ParseError, an_instance_of(String))
    allow(@opt).to receive(:puts)
    allow(@opt).to receive(:exit)
    @opt.parse "-u"
  end
end

RSpec.describe MSpecOptions, "#banner=" do
  before :each do
    @opt = MSpecOptions.new
  end

  it "sets the banner attribute" do
    expect(@opt.banner).to eq("")
    @opt.banner = "banner"
    expect(@opt.banner).to eq("banner")
  end
end

RSpec.describe MSpecOptions, "#width=" do
  before :each do
    @opt = MSpecOptions.new
  end

  it "sets the width attribute" do
    expect(@opt.width).to eq(30)
    @opt.width = 20
    expect(@opt.width).to eq(20)
  end
end

RSpec.describe MSpecOptions, "#config=" do
  before :each do
    @opt = MSpecOptions.new
  end

  it "sets the config attribute" do
    expect(@opt.config).to be_nil
    @opt.config = :config
    expect(@opt.config).to eq(:config)
  end
end

RSpec.describe MSpecOptions, "#doc" do
  before :each do
    @opt = MSpecOptions.new "command"
  end

  it "adds text to be displayed with #to_s" do
    @opt.doc "Some message"
    @opt.doc "Another message"
    expect(@opt.to_s).to eq <<-EOD
command

Some message
Another message
EOD
  end
end

RSpec.describe MSpecOptions, "#version" do
  before :each do
    @opt = MSpecOptions.new
    ScratchPad.clear
  end

  it "installs a basic -v, --version option" do
    expect(@opt).to receive(:puts)
    expect(@opt).to receive(:exit)
    @opt.version "1.0.0"
    @opt.parse "-v"
  end

  it "accepts a block instead of using the default block" do
    @opt.version("1.0.0") { |o| ScratchPad.record :version }
    @opt.parse "-v"
    expect(ScratchPad.recorded).to eq(:version)
  end
end

RSpec.describe MSpecOptions, "#help" do
  before :each do
    @opt = MSpecOptions.new
    ScratchPad.clear
  end

  it "installs a basic -h, --help option" do
    expect(@opt).to receive(:puts)
    expect(@opt).to receive(:exit).with(1)
    @opt.help
    @opt.parse "-h"
  end

  it "accepts a block instead of using the default block" do
    @opt.help { |o| ScratchPad.record :help }
    @opt.parse "-h"
    expect(ScratchPad.recorded).to eq(:help)
  end
end

RSpec.describe MSpecOptions, "#on_extra" do
  before :each do
    @opt = MSpecOptions.new
    ScratchPad.clear
  end

  it "registers a block to be called when an option is not recognized" do
    @opt.on_extra { ScratchPad.record :extra }
    @opt.parse "-g"
    expect(ScratchPad.recorded).to eq(:extra)
  end
end

RSpec.describe MSpecOptions, "#to_s" do
  before :each do
    @opt = MSpecOptions.new "command"
  end

  it "returns the banner and descriptive strings for all registered options" do
    @opt.on "-t", "--this ARG", "Adds this ARG to the list"
    expect(@opt.to_s).to eq <<-EOD
command

   -t, --this ARG             Adds this ARG to the list
EOD
  end
end

RSpec.describe "The -B, --config FILE option" do
  before :each do
    @options, @config = new_option
  end

  it "is enabled with #configure { }" do
    expect(@options).to receive(:on).with("-B", "--config", "FILE",
        an_instance_of(String))
    @options.configure {}
  end

  it "calls the passed block" do
    ["-B", "--config"].each do |opt|
      ScratchPad.clear

      @options.configure { |x| ScratchPad.record x }
      @options.parse [opt, "file"]
      expect(ScratchPad.recorded).to eq("file")
    end
  end
end

RSpec.describe "The -C, --chdir DIR option" do
  before :each do
    @options, @config = new_option
    @options.chdir
  end

  it "is enabled with #chdir" do
    expect(@options).to receive(:on).with("-C", "--chdir", "DIR",
        an_instance_of(String))
    @options.chdir
  end

  it "changes the working directory to DIR" do
    expect(Dir).to receive(:chdir).with("dir").twice
    ["-C", "--chdir"].each do |opt|
      @options.parse [opt, "dir"]
    end
  end
end

RSpec.describe "The --prefix STR option" do
  before :each do
    @options, @config = new_option
  end

  it "is enabled with #prefix" do
    expect(@options).to receive(:on).with("--prefix", "STR",
       an_instance_of(String))
    @options.prefix
  end

  it "sets the prefix config value" do
    @options.prefix
    @options.parse ["--prefix", "some/dir"]
    expect(@config[:prefix]).to eq("some/dir")
  end
end

RSpec.describe "The -t, --target TARGET option" do
  before :each do
    @options, @config = new_option
    @options.targets
  end

  it "is enabled with #targets" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-t", "--target", "TARGET",
        an_instance_of(String))
    @options.targets
  end

  it "sets the target to 'ruby' and flags to verbose with TARGET 'r' or 'ruby'" do
    ["-t", "--target"].each do |opt|
      ["r", "ruby"].each do |t|
        @config[:target] = nil
        @options.parse [opt, t]
        expect(@config[:target]).to eq("ruby")
      end
    end
  end

  it "sets the target to 'jruby' with TARGET 'j' or 'jruby'" do
    ["-t", "--target"].each do |opt|
      ["j", "jruby"].each do |t|
        @config[:target] = nil
        @options.parse [opt, t]
        expect(@config[:target]).to eq("jruby")
      end
    end
  end

  it "sets the target to 'shotgun/rubinius' with TARGET 'x' or 'rubinius'" do
    ["-t", "--target"].each do |opt|
      ["x", "rubinius"].each do |t|
        @config[:target] = nil
        @options.parse [opt, t]
        expect(@config[:target]).to eq("./bin/rbx")
      end
    end
  end

  it "set the target to 'rbx' with TARGET 'rbx'" do
    ["-t", "--target"].each do |opt|
      ["X", "rbx"].each do |t|
        @config[:target] = nil
        @options.parse [opt, t]
        expect(@config[:target]).to eq("rbx")
      end
    end
  end

  it "sets the target to 'maglev' with TARGET 'm' or 'maglev'" do
    ["-t", "--target"].each do |opt|
      ["m", "maglev"].each do |t|
        @config[:target] = nil
        @options.parse [opt, t]
        expect(@config[:target]).to eq("maglev-ruby")
      end
    end
  end

  it "sets the target to 'topaz' with TARGET 't' or 'topaz'" do
    ["-t", "--target"].each do |opt|
      ["t", "topaz"].each do |t|
        @config[:target] = nil
        @options.parse [opt, t]
        expect(@config[:target]).to eq("topaz")
      end
    end
  end

  it "sets the target to TARGET" do
    ["-t", "--target"].each do |opt|
      @config[:target] = nil
      @options.parse [opt, "whateva"]
      expect(@config[:target]).to eq("whateva")
    end
  end
end

RSpec.describe "The -T, --target-opt OPT option" do
  before :each do
    @options, @config = new_option
    @options.targets
  end

  it "is enabled with #targets" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-T", "--target-opt", "OPT",
        an_instance_of(String))
    @options.targets
  end

  it "adds OPT to flags" do
    ["-T", "--target-opt"].each do |opt|
      @config[:flags].delete "--whateva"
      @options.parse [opt, "--whateva"]
      expect(@config[:flags]).to include("--whateva")
    end
  end
end

RSpec.describe "The -I, --include DIR option" do
  before :each do
    @options, @config = new_option
    @options.targets
  end

  it "is enabled with #targets" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-I", "--include", "DIR",
        an_instance_of(String))
    @options.targets
  end

  it "add DIR to the load path" do
    ["-I", "--include"].each do |opt|
      @config[:loadpath].delete "-Ipackage"
      @options.parse [opt, "package"]
      expect(@config[:loadpath]).to include("-Ipackage")
    end
  end
end

RSpec.describe "The -r, --require LIBRARY option" do
  before :each do
    @options, @config = new_option
    @options.targets
  end

  it "is enabled with #targets" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-r", "--require", "LIBRARY",
        an_instance_of(String))
    @options.targets
  end

  it "adds LIBRARY to the requires list" do
    ["-r", "--require"].each do |opt|
      @config[:requires].delete "-rlibrick"
      @options.parse [opt, "librick"]
      expect(@config[:requires]).to include("-rlibrick")
    end
  end
end

RSpec.describe "The -f, --format FORMAT option" do
  before :each do
    @options, @config = new_option
    @options.formatters
  end

  it "is enabled with #formatters" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-f", "--format", "FORMAT",
        an_instance_of(String))
    @options.formatters
  end

  it "sets the SpecdocFormatter with FORMAT 's' or 'specdoc'" do
    ["-f", "--format"].each do |opt|
      ["s", "specdoc"].each do |f|
        @config[:formatter] = nil
        @options.parse [opt, f]
        expect(@config[:formatter]).to eq(SpecdocFormatter)
      end
    end
  end

  it "sets the HtmlFormatter with FORMAT 'h' or 'html'" do
    ["-f", "--format"].each do |opt|
      ["h", "html"].each do |f|
        @config[:formatter] = nil
        @options.parse [opt, f]
        expect(@config[:formatter]).to eq(HtmlFormatter)
      end
    end
  end

  it "sets the DottedFormatter with FORMAT 'd', 'dot' or 'dotted'" do
    ["-f", "--format"].each do |opt|
      ["d", "dot", "dotted"].each do |f|
        @config[:formatter] = nil
        @options.parse [opt, f]
        expect(@config[:formatter]).to eq(DottedFormatter)
      end
    end
  end

  it "sets the DescribeFormatter with FORMAT 'b' or 'describe'" do
    ["-f", "--format"].each do |opt|
      ["b", "describe"].each do |f|
        @config[:formatter] = nil
        @options.parse [opt, f]
        expect(@config[:formatter]).to eq(DescribeFormatter)
      end
    end
  end

  it "sets the FileFormatter with FORMAT 'f', 'file'" do
    ["-f", "--format"].each do |opt|
      ["f", "file"].each do |f|
        @config[:formatter] = nil
        @options.parse [opt, f]
        expect(@config[:formatter]).to eq(FileFormatter)
      end
    end
  end

  it "sets the UnitdiffFormatter with FORMAT 'u', 'unit', or 'unitdiff'" do
    ["-f", "--format"].each do |opt|
      ["u", "unit", "unitdiff"].each do |f|
        @config[:formatter] = nil
        @options.parse [opt, f]
        expect(@config[:formatter]).to eq(UnitdiffFormatter)
      end
    end
  end

  it "sets the SummaryFormatter with FORMAT 'm' or 'summary'" do
    ["-f", "--format"].each do |opt|
      ["m", "summary"].each do |f|
        @config[:formatter] = nil
        @options.parse [opt, f]
        expect(@config[:formatter]).to eq(SummaryFormatter)
      end
    end
  end

  it "sets the SpinnerFormatter with FORMAT 'a', '*', or 'spin'" do
    ["-f", "--format"].each do |opt|
      ["a", "*", "spin"].each do |f|
        @config[:formatter] = nil
        @options.parse [opt, f]
        expect(@config[:formatter]).to eq(SpinnerFormatter)
      end
    end
  end

  it "sets the MethodFormatter with FORMAT 't' or 'method'" do
    ["-f", "--format"].each do |opt|
      ["t", "method"].each do |f|
        @config[:formatter] = nil
        @options.parse [opt, f]
        expect(@config[:formatter]).to eq(MethodFormatter)
      end
    end
  end

  it "sets the YamlFormatter with FORMAT 'y' or 'yaml'" do
    ["-f", "--format"].each do |opt|
      ["y", "yaml"].each do |f|
        @config[:formatter] = nil
        @options.parse [opt, f]
        expect(@config[:formatter]).to eq(YamlFormatter)
      end
    end
  end

  it "sets the JUnitFormatter with FORMAT 'j' or 'junit'" do
    ["-f", "--format"].each do |opt|
      ["j", "junit"].each do |f|
        @config[:formatter] = nil
        @options.parse [opt, f]
        expect(@config[:formatter]).to eq(JUnitFormatter)
      end
    end
  end
end

RSpec.describe "The -o, --output FILE option" do
  before :each do
    @options, @config = new_option
    @options.formatters
  end

  it "is enabled with #formatters" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-o", "--output", "FILE",
        an_instance_of(String))
    @options.formatters
  end

  it "sets the output to FILE" do
    ["-o", "--output"].each do |opt|
      @config[:output] = nil
      @options.parse [opt, "some/file"]
      expect(@config[:output]).to eq("some/file")
    end
  end
end

RSpec.describe "The -e, --example STR" do
  before :each do
    @options, @config = new_option
    @options.filters
  end

  it "is enabled with #filters" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-e", "--example", "STR",
        an_instance_of(String))
    @options.filters
  end

  it "adds STR to the includes list" do
    ["-e", "--example"].each do |opt|
      @config[:includes] = []
      @options.parse [opt, "this spec"]
      expect(@config[:includes]).to include("this spec")
    end
  end
end

RSpec.describe "The -E, --exclude STR" do
  before :each do
    @options, @config = new_option
    @options.filters
  end

  it "is enabled with #filters" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-E", "--exclude", "STR",
        an_instance_of(String))
    @options.filters
  end

  it "adds STR to the excludes list" do
    ["-E", "--exclude"].each do |opt|
      @config[:excludes] = []
      @options.parse [opt, "this spec"]
      expect(@config[:excludes]).to include("this spec")
    end
  end
end

RSpec.describe "The -p, --pattern PATTERN" do
  before :each do
    @options, @config = new_option
    @options.filters
  end

  it "is enabled with #filters" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-p", "--pattern", "PATTERN",
        an_instance_of(String))
    @options.filters
  end

  it "adds PATTERN to the included patterns list" do
    ["-p", "--pattern"].each do |opt|
      @config[:patterns] = []
      @options.parse [opt, "this spec"]
      expect(@config[:patterns]).to include(/this spec/)
    end
  end
end

RSpec.describe "The -P, --excl-pattern PATTERN" do
  before :each do
    @options, @config = new_option
    @options.filters
  end

  it "is enabled with #filters" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-P", "--excl-pattern", "PATTERN",
        an_instance_of(String))
    @options.filters
  end

  it "adds PATTERN to the excluded patterns list" do
    ["-P", "--excl-pattern"].each do |opt|
      @config[:xpatterns] = []
      @options.parse [opt, "this spec"]
      expect(@config[:xpatterns]).to include(/this spec/)
    end
  end
end

RSpec.describe "The -g, --tag TAG" do
  before :each do
    @options, @config = new_option
    @options.filters
  end

  it "is enabled with #filters" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-g", "--tag", "TAG",
        an_instance_of(String))
    @options.filters
  end

  it "adds TAG to the included tags list" do
    ["-g", "--tag"].each do |opt|
      @config[:tags] = []
      @options.parse [opt, "this spec"]
      expect(@config[:tags]).to include("this spec")
    end
  end
end

RSpec.describe "The -G, --excl-tag TAG" do
  before :each do
    @options, @config = new_option
    @options.filters
  end

  it "is enabled with #filters" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-G", "--excl-tag", "TAG",
        an_instance_of(String))
    @options.filters
  end

  it "adds TAG to the excluded tags list" do
    ["-G", "--excl-tag"].each do |opt|
      @config[:xtags] = []
      @options.parse [opt, "this spec"]
      expect(@config[:xtags]).to include("this spec")
    end
  end
end

RSpec.describe "The -w, --profile FILE option" do
  before :each do
    @options, @config = new_option
    @options.filters
  end

  it "is enabled with #filters" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-w", "--profile", "FILE",
        an_instance_of(String))
    @options.filters
  end

  it "adds FILE to the included profiles list" do
    ["-w", "--profile"].each do |opt|
      @config[:profiles] = []
      @options.parse [opt, "spec/profiles/rails.yaml"]
      expect(@config[:profiles]).to include("spec/profiles/rails.yaml")
    end
  end
end

RSpec.describe "The -W, --excl-profile FILE option" do
  before :each do
    @options, @config = new_option
    @options.filters
  end

  it "is enabled with #filters" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-W", "--excl-profile", "FILE",
        an_instance_of(String))
    @options.filters
  end

  it "adds FILE to the excluded profiles list" do
    ["-W", "--excl-profile"].each do |opt|
      @config[:xprofiles] = []
      @options.parse [opt, "spec/profiles/rails.yaml"]
      expect(@config[:xprofiles]).to include("spec/profiles/rails.yaml")
    end
  end
end

RSpec.describe "The -Z, --dry-run option" do
  before :each do
    @options, @config = new_option
    @options.pretend
  end

  it "is enabled with #pretend" do
    expect(@options).to receive(:on).with("-Z", "--dry-run", an_instance_of(String))
    @options.pretend
  end

  it "registers the MSpec pretend mode" do
    expect(MSpec).to receive(:register_mode).with(:pretend).twice
    ["-Z", "--dry-run"].each do |opt|
      @options.parse opt
    end
  end
end

RSpec.describe "The --unguarded option" do
  before :each do
    @options, @config = new_option
    @options.unguarded
  end

  it "is enabled with #unguarded" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("--unguarded", an_instance_of(String))
    @options.unguarded
  end

  it "registers the MSpec unguarded mode" do
    expect(MSpec).to receive(:register_mode).with(:unguarded)
    @options.parse "--unguarded"
  end
end

RSpec.describe "The --no-ruby_guard option" do
  before :each do
    @options, @config = new_option
    @options.unguarded
  end

  it "is enabled with #unguarded" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("--no-ruby_bug", an_instance_of(String))
    @options.unguarded
  end

  it "registers the MSpec no_ruby_bug mode" do
    expect(MSpec).to receive(:register_mode).with(:no_ruby_bug)
    @options.parse "--no-ruby_bug"
  end
end

RSpec.describe "The -H, --random option" do
  before :each do
    @options, @config = new_option
    @options.randomize
  end

  it "is enabled with #randomize" do
    expect(@options).to receive(:on).with("-H", "--random", an_instance_of(String))
    @options.randomize
  end

  it "registers the MSpec randomize mode" do
    expect(MSpec).to receive(:randomize=).twice
    ["-H", "--random"].each do |opt|
      @options.parse opt
    end
  end
end

RSpec.describe "The -R, --repeat option" do
  before :each do
    @options, @config = new_option
    @options.repeat
  end

  it "is enabled with #repeat" do
    expect(@options).to receive(:on).with("-R", "--repeat", "NUMBER", an_instance_of(String))
    @options.repeat
  end

  it "registers the MSpec repeat mode" do
    ["-R", "--repeat"].each do |opt|
      MSpec.repeat = 1
      @options.parse [opt, "10"]
      repeat_count = 0
      MSpec.repeat do
        repeat_count += 1
      end
      expect(repeat_count).to eq(10)
    end
  end
end

RSpec.describe "The -V, --verbose option" do
  before :each do
    @options, @config = new_option
    @options.verbose
  end

  it "is enabled with #verbose" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-V", "--verbose", an_instance_of(String))
    @options.verbose
  end

  it "registers a verbose output object with MSpec" do
    expect(MSpec).to receive(:register).with(:start, anything()).twice
    expect(MSpec).to receive(:register).with(:load, anything()).twice
    ["-V", "--verbose"].each do |opt|
      @options.parse opt
    end
  end
end

RSpec.describe "The -m, --marker MARKER option" do
  before :each do
    @options, @config = new_option
    @options.verbose
  end

  it "is enabled with #verbose" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-m", "--marker", "MARKER",
        an_instance_of(String))
    @options.verbose
  end

  it "registers a marker output object with MSpec" do
    expect(MSpec).to receive(:register).with(:load, anything()).twice
    ["-m", "--marker"].each do |opt|
      @options.parse [opt, ","]
    end
  end
end

RSpec.describe "The --int-spec option" do
  before :each do
    @options, @config = new_option
    @options.interrupt
  end

  it "is enabled with #interrupt" do
    expect(@options).to receive(:on).with("--int-spec", an_instance_of(String))
    @options.interrupt
  end

  it "sets the abort config option to false to only abort the running spec with ^C" do
    @config[:abort] = true
    @options.parse "--int-spec"
    expect(@config[:abort]).to eq(false)
  end
end

RSpec.describe "The -Y, --verify option" do
  before :each do
    @options, @config = new_option
    @options.verify
  end

  it "is enabled with #interrupt" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-Y", "--verify", an_instance_of(String))
    @options.verify
  end

  it "sets the MSpec mode to :verify" do
    expect(MSpec).to receive(:register_mode).with(:verify).twice
    ["-Y", "--verify"].each do |m|
      @options.parse m
    end
  end
end

RSpec.describe "The -O, --report option" do
  before :each do
    @options, @config = new_option
    @options.verify
  end

  it "is enabled with #interrupt" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-O", "--report", an_instance_of(String))
    @options.verify
  end

  it "sets the MSpec mode to :report" do
    expect(MSpec).to receive(:register_mode).with(:report).twice
    ["-O", "--report"].each do |m|
      @options.parse m
    end
  end
end

RSpec.describe "The --report-on GUARD option" do
  before :each do
    allow(MSpec).to receive(:register_mode)

    @options, @config = new_option
    @options.verify

    SpecGuard.clear_guards
  end

  after :each do
    SpecGuard.clear_guards
  end

  it "is enabled with #interrupt" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("--report-on", "GUARD", an_instance_of(String))
    @options.verify
  end

  it "sets the MSpec mode to :report_on" do
    expect(MSpec).to receive(:register_mode).with(:report_on)
    @options.parse ["--report-on", "ruby_bug"]
  end

  it "converts the guard name to a symbol" do
    name = double("ruby_bug")
    expect(name).to receive(:to_sym)
    @options.parse ["--report-on", name]
  end

  it "saves the name of the guard" do
    @options.parse ["--report-on", "ruby_bug"]
    expect(SpecGuard.guards).to eq([:ruby_bug])
  end
end

RSpec.describe "The -K, --action-tag TAG option" do
  before :each do
    @options, @config = new_option
    @options.action_filters
  end

  it "is enabled with #action_filters" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-K", "--action-tag", "TAG",
        an_instance_of(String))
    @options.action_filters
  end

  it "adds TAG to the list of tags that trigger actions" do
    ["-K", "--action-tag"].each do |opt|
      @config[:atags] = []
      @options.parse [opt, "action-tag"]
      expect(@config[:atags]).to include("action-tag")
    end
  end
end

RSpec.describe "The -S, --action-string STR option" do
  before :each do
    @options, @config = new_option
    @options.action_filters
  end

  it "is enabled with #action_filters" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-S", "--action-string", "STR",
        an_instance_of(String))
    @options.action_filters
  end

  it "adds STR to the list of spec descriptions that trigger actions" do
    ["-S", "--action-string"].each do |opt|
      @config[:astrings] = []
      @options.parse [opt, "action-str"]
      expect(@config[:astrings]).to include("action-str")
    end
  end
end

RSpec.describe "The -d, --debug option" do
  before :each do
    @options, @config = new_option
    @options.debug
  end

  after :each do
    $MSPEC_DEBUG = nil
  end

  it "is enabled with #debug" do
    allow(@options).to receive(:on)
    expect(@options).to receive(:on).with("-d", "--debug", an_instance_of(String))
    @options.debug
  end

  it "sets $MSPEC_DEBUG to true" do
    ["-d", "--debug"].each do |opt|
      expect($MSPEC_DEBUG).not_to be_truthy
      @options.parse opt
      expect($MSPEC_DEBUG).to be_truthy
      $MSPEC_DEBUG = nil
    end
  end
end

RSpec.describe "MSpecOptions#all" do
  it "includes all options" do
    meth = MSpecOptions.instance_method(:all)
    file, line = meth.source_location
    contents = File.read(file)
    lines = contents.lines

    from = line
    to = from
    to += 1 until /^\s*end\s*$/ =~ lines[to]
    calls = lines[from...to].map(&:strip)

    option_methods = contents.scan(/def (\w+).*\n\s*on\(/).map(&:first)
    option_methods[0].sub!("configure", "configure {}")

    expect(calls).to eq(option_methods)
  end
end
