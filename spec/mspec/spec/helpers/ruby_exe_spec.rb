require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'
require 'rbconfig'

class RubyExeSpecs
  public :ruby_exe_options
  public :resolve_ruby_exe
  public :ruby_cmd
  public :ruby_exe
end

RSpec.describe "#ruby_exe_options" do
  before :each do
    @ruby_exe_env = ENV['RUBY_EXE']
    @script = RubyExeSpecs.new
  end

  after :each do
    ENV['RUBY_EXE'] = @ruby_exe_env
  end

  it "returns ENV['RUBY_EXE'] when passed :env" do
    ENV['RUBY_EXE'] = "kowabunga"
    expect(@script.ruby_exe_options(:env)).to eq("kowabunga")
  end

  it "returns 'bin/jruby' when passed :engine and RUBY_ENGINE is 'jruby'" do
    stub_const "RUBY_ENGINE", 'jruby'
    expect(@script.ruby_exe_options(:engine)).to eq('bin/jruby')
  end

  it "returns 'bin/rbx' when passed :engine, RUBY_ENGINE is 'rbx'" do
    stub_const "RUBY_ENGINE", 'rbx'
    expect(@script.ruby_exe_options(:engine)).to eq('bin/rbx')
  end

  it "returns 'ir' when passed :engine and RUBY_ENGINE is 'ironruby'" do
    stub_const "RUBY_ENGINE", 'ironruby'
    expect(@script.ruby_exe_options(:engine)).to eq('ir')
  end

  it "returns 'maglev-ruby' when passed :engine and RUBY_ENGINE is 'maglev'" do
    stub_const "RUBY_ENGINE", 'maglev'
    expect(@script.ruby_exe_options(:engine)).to eq('maglev-ruby')
  end

  it "returns 'topaz' when passed :engine and RUBY_ENGINE is 'topaz'" do
    stub_const "RUBY_ENGINE", 'topaz'
    expect(@script.ruby_exe_options(:engine)).to eq('topaz')
  end

  it "returns RUBY_ENGINE + $(EXEEXT) when passed :name" do
    bin = RUBY_ENGINE + (RbConfig::CONFIG['EXEEXT'] || RbConfig::CONFIG['exeext'] || '')
    name = File.join ".", bin
    expect(@script.ruby_exe_options(:name)).to eq(name)
  end

  it "returns $(bindir)/$(RUBY_INSTALL_NAME) + $(EXEEXT) when passed :install_name" do
    bin = RbConfig::CONFIG['RUBY_INSTALL_NAME'] + (RbConfig::CONFIG['EXEEXT'] || RbConfig::CONFIG['exeext'] || '')
    name = File.join RbConfig::CONFIG['bindir'], bin
    expect(@script.ruby_exe_options(:install_name)).to eq(name)
  end
end

RSpec.describe "#resolve_ruby_exe" do
  before :each do
    @name = "ruby_spec_exe"
    @script = RubyExeSpecs.new
  end

  it "returns the value returned by #ruby_exe_options if it exists and is executable" do
    expect(@script).to receive(:ruby_exe_options).and_return(@name)
    expect(File).to receive(:file?).with(@name).and_return(true)
    expect(File).to receive(:executable?).with(@name).and_return(true)
    expect(File).to receive(:expand_path).with(@name).and_return(@name)
    expect(@script.resolve_ruby_exe).to eq(@name)
  end

  it "expands the path portion of the result of #ruby_exe_options" do
    expect(@script).to receive(:ruby_exe_options).and_return("#{@name}")
    expect(File).to receive(:file?).with(@name).and_return(true)
    expect(File).to receive(:executable?).with(@name).and_return(true)
    expect(File).to receive(:expand_path).with(@name).and_return("/usr/bin/#{@name}")
    expect(@script.resolve_ruby_exe).to eq("/usr/bin/#{@name}")
  end

  it "adds the flags after the executable" do
    @name = 'bin/rbx'
    expect(@script).to receive(:ruby_exe_options).and_return(@name)
    expect(File).to receive(:file?).with(@name).and_return(true)
    expect(File).to receive(:executable?).with(@name).and_return(true)
    expect(File).to receive(:expand_path).with(@name).and_return(@name)

    expect(ENV).to receive(:[]).with("RUBY_FLAGS").and_return('-X19')
    expect(@script.resolve_ruby_exe).to eq('bin/rbx -X19')
  end

  it "raises an exception if no exe is found" do
    expect(File).to receive(:file?).at_least(:once).and_return(false)
    expect {
      @script.resolve_ruby_exe
    }.to raise_error(Exception)
  end
end

RSpec.describe Object, "#ruby_cmd" do
  before :each do
    stub_const 'RUBY_EXE', 'ruby_spec_exe -w -Q'

    @file = "some/ruby/file.rb"
    @code = %(some "real" 'ruby' code)

    @script = RubyExeSpecs.new
  end

  it "returns a command that runs the given file if it is a file that exists" do
    expect(File).to receive(:exist?).with(@file).and_return(true)
    expect(@script.ruby_cmd(@file)).to eq("ruby_spec_exe -w -Q some/ruby/file.rb")
  end

  it "includes the given options and arguments with a file" do
    expect(File).to receive(:exist?).with(@file).and_return(true)
    expect(@script.ruby_cmd(@file, :options => "-w -Cdir", :args => "< file.txt")).to eq(
      "ruby_spec_exe -w -Q -w -Cdir some/ruby/file.rb < file.txt"
    )
  end

  it "includes the given options and arguments with -e" do
    expect(File).to receive(:exist?).with(@code).and_return(false)
    expect(@script.ruby_cmd(@code, :options => "-W0 -Cdir", :args => "< file.txt")).to eq(
      %(ruby_spec_exe -w -Q -W0 -Cdir -e "some \\"real\\" 'ruby' code" < file.txt)
    )
  end

  it "returns a command with options and arguments but without code or file" do
    expect(@script.ruby_cmd(nil, :options => "-c", :args => "> file.txt")).to eq(
      "ruby_spec_exe -w -Q -c > file.txt"
    )
  end
end

RSpec.describe Object, "#ruby_exe" do
  before :each do
    stub_const 'RUBY_EXE', 'ruby_spec_exe -w -Q'

    @script = RubyExeSpecs.new
    allow(@script).to receive(:`)

    status_successful = double(Process::Status,  exitstatus: 0)
    allow(Process).to receive(:last_status).and_return(status_successful)
  end

  it "returns command STDOUT when given command" do
    code = "code"
    options = {}
    output = "output"
    allow(@script).to receive(:`).and_return(output)

    expect(@script.ruby_exe(code, options)).to eq output
  end

  it "returns an Array containing the interpreter executable and flags when given no arguments" do
    expect(@script.ruby_exe).to eq(['ruby_spec_exe', '-w', '-Q'])
  end

  it "executes (using `) the result of calling #ruby_cmd with the given arguments" do
    code = "code"
    options = {}
    expect(@script).to receive(:ruby_cmd).and_return("ruby_cmd")
    expect(@script).to receive(:`).with("ruby_cmd")
    @script.ruby_exe(code, options)
  end

  it "raises exception when command exit status is not successful" do
    code = "code"
    options = {}

    status_failed = double(Process::Status, exitstatus: 4)
    allow(Process).to receive(:last_status).and_return(status_failed)

    expect {
      @script.ruby_exe(code, options)
    }.to raise_error(%r{Expected exit status is 0 but actual is 4 for command ruby_exe\(.+\)})
  end

  it "shows in the exception message if exitstatus is nil (e.g., signal)" do
    code = "code"
    options = {}

    status_failed = double(Process::Status, exitstatus: nil)
    allow(Process).to receive(:last_status).and_return(status_failed)

    expect {
      @script.ruby_exe(code, options)
    }.to raise_error(%r{Expected exit status is 0 but actual is nil for command ruby_exe\(.+\)})
  end

  describe "with :dir option" do
    it "is deprecated" do
      expect {
        @script.ruby_exe nil, :dir => "tmp"
      }.to raise_error(/no longer supported, use Dir\.chdir/)
    end
  end

  describe "with :env option" do
    it "preserves the values of existing ENV keys" do
      ENV["ABC"] = "123"
      allow(ENV).to receive(:[])
      expect(ENV).to receive(:[]).with("ABC")
      @script.ruby_exe nil, :env => { :ABC => "xyz" }
    end

    it "adds the :env entries to ENV" do
      expect(ENV).to receive(:[]=).with("ABC", "xyz")
      @script.ruby_exe nil, :env => { :ABC => "xyz" }
    end

    it "deletes the :env entries in ENV when an exception is raised" do
      expect(ENV).to receive(:delete).with("XYZ")
      @script.ruby_exe nil, :env => { :XYZ => "xyz" }
    end

    it "resets the values of existing ENV keys when an exception is raised" do
      ENV["ABC"] = "123"
      expect(ENV).to receive(:[]=).with("ABC", "xyz")
      expect(ENV).to receive(:[]=).with("ABC", "123")

      expect(@script).to receive(:`).and_raise(Exception)
      expect do
        @script.ruby_exe nil, :env => { :ABC => "xyz" }
      end.to raise_error(Exception)
    end
  end

  describe "with :exit_status option" do
    before do
      status_failed = double(Process::Status, exitstatus: 4)
      allow(Process).to receive(:last_status).and_return(status_failed)
    end

    it "raises exception when command ends with not expected status" do
      expect {
        @script.ruby_exe("path", exit_status: 1)
      }.to raise_error(%r{Expected exit status is 1 but actual is 4 for command ruby_exe\(.+\)})
    end

    it "does not raise exception when command ends with expected status" do
      output = "output"
      allow(@script).to receive(:`).and_return(output)

      expect(@script.ruby_exe("path", exit_status: 4)).to eq output
    end
  end
end
