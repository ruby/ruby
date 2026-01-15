require_relative '../../spec_helper'

describe "Interrupt.new" do
  it "returns an instance of interrupt with no message given" do
    e = Interrupt.new
    e.signo.should == Signal.list["INT"]
    e.signm.should == "Interrupt"
  end

  it "takes an optional message argument" do
    e = Interrupt.new("message")
    e.signo.should == Signal.list["INT"]
    e.signm.should == "message"
  end
end

describe "rescuing Interrupt" do
  before do
    @original_sigint_proc = Signal.trap(:INT, :SIG_DFL)
  end

  after do
    Signal.trap(:INT, @original_sigint_proc)
  end

  it "raises an Interrupt when sent a signal SIGINT" do
    begin
      Process.kill :INT, Process.pid
      sleep
    rescue Interrupt => e
      e.signo.should == Signal.list["INT"]
      ["", "Interrupt"].should.include?(e.message)
    end
  end
end

describe "Interrupt" do
  # This spec is basically the same as above,
  # but it does not rely on Signal.trap(:INT, :SIG_DFL) which can be tricky
  it "is raised on the main Thread by the default SIGINT handler" do
    out = ruby_exe(<<-'RUBY', args: "2>&1")
    begin
      Process.kill :INT, Process.pid
      sleep
    rescue Interrupt => e
      puts "Interrupt: #{e.signo}"
    end
    RUBY
    out.should == "Interrupt: #{Signal.list["INT"]}\n"
  end

  platform_is_not :windows do
    it "shows the backtrace and has a signaled exit status" do
      err = IO.popen([*ruby_exe, '-e', 'Process.kill :INT, Process.pid; sleep'], err: [:child, :out], &:read)
      $?.termsig.should == Signal.list.fetch('INT')
      err.should.include? ': Interrupt'
      err.should =~ /from -e:1:in [`']<main>'/
    end
  end
end
