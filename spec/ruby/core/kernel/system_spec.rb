require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#system" do
  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:system)
  end

  it "executes the specified command in a subprocess" do
    -> { system("echo a") }.should output_to_fd("a\n")

    $?.should.instance_of? Process::Status
    $?.should.success?
  end

  it "returns true when the command exits with a zero exit status" do
    system(ruby_cmd('exit 0')).should == true

    $?.should.instance_of? Process::Status
    $?.should.success?
    $?.exitstatus.should == 0
  end

  it "returns false when the command exits with a non-zero exit status" do
    system(ruby_cmd('exit 1')).should == false

    $?.should.instance_of? Process::Status
    $?.should_not.success?
    $?.exitstatus.should == 1
  end

  it "raises RuntimeError when `exception: true` is given and the command exits with a non-zero exit status" do
    -> { system(ruby_cmd('exit 1'), exception: true) }.should.raise(RuntimeError)
  end

  it "raises Errno::ENOENT when `exception: true` is given and the specified command does not exist" do
    -> { system('feature_14386', exception: true) }.should.raise(Errno::ENOENT)
  end

  it "returns nil when command execution fails" do
    system("sad").should == nil

    $?.should.instance_of? Process::Status
    $?.pid.should.is_a?(Integer)
    $?.should_not.success?
  end

  it "does not write to stderr when command execution fails" do
    -> { system("sad") }.should output_to_fd("", STDERR)
  end

  platform_is_not :windows do
    before :each do
      @shell = ENV['SHELL']
    end

    after :each do
      ENV['SHELL'] = @shell
    end

    it "executes with `sh` if the command contains shell characters" do
      -> { system("echo $0") }.should output_to_fd("sh\n")
    end

    it "ignores SHELL env var and always uses `sh`" do
      ENV['SHELL'] = "/bin/fakeshell"
      -> { system("echo $0") }.should output_to_fd("sh\n")
    end
  end

  platform_is_not :windows do
    before :each do
      require 'tmpdir'
      @shell_command = File.join(Dir.mktmpdir, "noshebang.cmd")
      File.write(@shell_command, %[echo "$PATH"\n], perm: 0o700)
    end

    after :each do
      File.unlink(@shell_command)
      Dir.rmdir(File.dirname(@shell_command))
    end

    it "executes with `sh` if the command is executable but not binary and there is no shebang" do
      -> { system(@shell_command) }.should output_to_fd(ENV['PATH'] + "\n")
    end
  end

  before :each do
    ENV['TEST_SH_EXPANSION'] = 'foo'
    @shell_var = '$TEST_SH_EXPANSION'
    platform_is :windows do
      @shell_var = '%TEST_SH_EXPANSION%'
    end
  end

  after :each do
    ENV.delete('TEST_SH_EXPANSION')
  end

  it "expands shell variables when given a single string argument" do
    -> { system("echo #{@shell_var}") }.should output_to_fd("foo\n")
  end

  platform_is_not :windows do
    it "does not expand shell variables when given multiples arguments" do
      -> { system("echo", @shell_var) }.should output_to_fd("#{@shell_var}\n")
    end
  end

  platform_is :windows do
    it "does expand shell variables when given multiples arguments" do
      # See https://bugs.ruby-lang.org/issues/12231
      -> { system("echo", @shell_var) }.should output_to_fd("foo\n")
    end
  end

  platform_is :windows do
    it "runs commands starting with any number of @ using shell" do
      `#{ruby_cmd("p system 'does_not_exist'")} 2>NUL`.chomp.should == "nil"
      system('@does_not_exist 2>NUL').should == false
      system("@@@#{ruby_cmd('exit 0')}").should == true
    end
  end
end

describe "Kernel.system" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:system)
  end
end
