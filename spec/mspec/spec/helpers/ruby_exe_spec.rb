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

describe "#ruby_exe_options" do
  before :each do
    @ruby_exe_env = ENV['RUBY_EXE']
    @script = RubyExeSpecs.new
  end

  after :each do
    ENV['RUBY_EXE'] = @ruby_exe_env
  end

  it "returns ENV['RUBY_EXE'] when passed :env" do
    ENV['RUBY_EXE'] = "kowabunga"
    @script.ruby_exe_options(:env).should == "kowabunga"
  end

  it "returns 'bin/jruby' when passed :engine and RUBY_ENGINE is 'jruby'" do
    stub_const "RUBY_ENGINE", 'jruby'
    @script.ruby_exe_options(:engine).should == 'bin/jruby'
  end

  it "returns 'bin/rbx' when passed :engine, RUBY_ENGINE is 'rbx'" do
    stub_const "RUBY_ENGINE", 'rbx'
    @script.ruby_exe_options(:engine).should == 'bin/rbx'
  end

  it "returns 'ir' when passed :engine and RUBY_ENGINE is 'ironruby'" do
    stub_const "RUBY_ENGINE", 'ironruby'
    @script.ruby_exe_options(:engine).should == 'ir'
  end

  it "returns 'maglev-ruby' when passed :engine and RUBY_ENGINE is 'maglev'" do
    stub_const "RUBY_ENGINE", 'maglev'
    @script.ruby_exe_options(:engine).should == 'maglev-ruby'
  end

  it "returns 'topaz' when passed :engine and RUBY_ENGINE is 'topaz'" do
    stub_const "RUBY_ENGINE", 'topaz'
    @script.ruby_exe_options(:engine).should == 'topaz'
  end

  it "returns RUBY_ENGINE + $(EXEEXT) when passed :name" do
    bin = RUBY_ENGINE + (RbConfig::CONFIG['EXEEXT'] || RbConfig::CONFIG['exeext'] || '')
    name = File.join ".", bin
    @script.ruby_exe_options(:name).should == name
  end

  it "returns $(bindir)/$(RUBY_INSTALL_NAME) + $(EXEEXT) when passed :install_name" do
    bin = RbConfig::CONFIG['RUBY_INSTALL_NAME'] + (RbConfig::CONFIG['EXEEXT'] || RbConfig::CONFIG['exeext'] || '')
    name = File.join RbConfig::CONFIG['bindir'], bin
    @script.ruby_exe_options(:install_name).should == name
  end
end

describe "#resolve_ruby_exe" do
  before :each do
    @name = "ruby_spec_exe"
    @script = RubyExeSpecs.new
  end

  it "returns the value returned by #ruby_exe_options if it exists and is executable" do
    @script.should_receive(:ruby_exe_options).and_return(@name)
    File.should_receive(:file?).with(@name).and_return(true)
    File.should_receive(:executable?).with(@name).and_return(true)
    File.should_receive(:expand_path).with(@name).and_return(@name)
    @script.resolve_ruby_exe.should == @name
  end

  it "expands the path portion of the result of #ruby_exe_options" do
    @script.should_receive(:ruby_exe_options).and_return("#{@name}")
    File.should_receive(:file?).with(@name).and_return(true)
    File.should_receive(:executable?).with(@name).and_return(true)
    File.should_receive(:expand_path).with(@name).and_return("/usr/bin/#{@name}")
    @script.resolve_ruby_exe.should == "/usr/bin/#{@name}"
  end

  it "adds the flags after the executable" do
    @name = 'bin/rbx'
    @script.should_receive(:ruby_exe_options).and_return(@name)
    File.should_receive(:file?).with(@name).and_return(true)
    File.should_receive(:executable?).with(@name).and_return(true)
    File.should_receive(:expand_path).with(@name).and_return(@name)

    ENV.should_receive(:[]).with("RUBY_FLAGS").and_return('-X19')
    @script.resolve_ruby_exe.should == 'bin/rbx -X19'
  end

  it "raises an exception if no exe is found" do
    File.should_receive(:file?).at_least(:once).and_return(false)
    lambda {
      @script.resolve_ruby_exe
    }.should raise_error(Exception)
  end
end

describe Object, "#ruby_cmd" do
  before :each do
    stub_const 'RUBY_EXE', 'ruby_spec_exe -w -Q'

    @file = "some/ruby/file.rb"
    @code = %(some "real" 'ruby' code)

    @script = RubyExeSpecs.new
  end

  it "returns a command that runs the given file if it is a file that exists" do
    File.should_receive(:exist?).with(@file).and_return(true)
    @script.ruby_cmd(@file).should == "ruby_spec_exe -w -Q some/ruby/file.rb"
  end

  it "includes the given options and arguments with a file" do
    File.should_receive(:exist?).with(@file).and_return(true)
    @script.ruby_cmd(@file, :options => "-w -Cdir", :args => "< file.txt").should ==
      "ruby_spec_exe -w -Q -w -Cdir some/ruby/file.rb < file.txt"
  end

  it "includes the given options and arguments with -e" do
    File.should_receive(:exist?).with(@code).and_return(false)
    @script.ruby_cmd(@code, :options => "-W0 -Cdir", :args => "< file.txt").should ==
      %(ruby_spec_exe -w -Q -W0 -Cdir -e "some \\"real\\" 'ruby' code" < file.txt)
  end

  it "returns a command with options and arguments but without code or file" do
    @script.ruby_cmd(nil, :options => "-c", :args => "> file.txt").should ==
      "ruby_spec_exe -w -Q -c > file.txt"
  end
end

describe Object, "#ruby_exe" do
  before :each do
    stub_const 'RUBY_EXE', 'ruby_spec_exe -w -Q'

    @script = RubyExeSpecs.new
    @script.stub(:`)
  end

  it "returns an Array containing the interpreter executable and flags when given no arguments" do
    @script.ruby_exe.should == ['ruby_spec_exe', '-w', '-Q']
  end

  it "executes (using `) the result of calling #ruby_cmd with the given arguments" do
    code = "code"
    options = {}
    @script.should_receive(:ruby_cmd).and_return("ruby_cmd")
    @script.should_receive(:`).with("ruby_cmd")
    @script.ruby_exe(code, options)
  end

  describe "with :dir option" do
    it "is deprecated" do
      lambda {
        @script.ruby_exe nil, :dir => "tmp"
      }.should raise_error(/no longer supported, use Dir\.chdir/)
    end
  end

  describe "with :env option" do
    it "preserves the values of existing ENV keys" do
      ENV["ABC"] = "123"
      ENV.stub(:[])
      ENV.should_receive(:[]).with("ABC")
      @script.ruby_exe nil, :env => { :ABC => "xyz" }
    end

    it "adds the :env entries to ENV" do
      ENV.should_receive(:[]=).with("ABC", "xyz")
      @script.ruby_exe nil, :env => { :ABC => "xyz" }
    end

    it "deletes the :env entries in ENV when an exception is raised" do
      ENV.should_receive(:delete).with("XYZ")
      @script.ruby_exe nil, :env => { :XYZ => "xyz" }
    end

    it "resets the values of existing ENV keys when an exception is raised" do
      ENV["ABC"] = "123"
      ENV.should_receive(:[]=).with("ABC", "xyz")
      ENV.should_receive(:[]=).with("ABC", "123")

      @script.should_receive(:`).and_raise(Exception)
      lambda do
        @script.ruby_exe nil, :env => { :ABC => "xyz" }
      end.should raise_error(Exception)
    end
  end
end
