require_relative '../../spec_helper'

describe "Thread.report_on_exception" do
  it "defaults to true" do
    ruby_exe("p Thread.report_on_exception").should == "true\n"
  end
end

describe "Thread.report_on_exception=" do
  before :each do
    @report_on_exception = Thread.report_on_exception
  end

  after :each do
    Thread.report_on_exception = @report_on_exception
  end

  it "changes the default value for new threads" do
    Thread.report_on_exception = true
    Thread.report_on_exception.should == true
    t = Thread.new {}
    t.join
    t.report_on_exception.should == true
  end
end

describe "Thread#report_on_exception" do
  it "returns true for the main Thread" do
    Thread.current.report_on_exception.should == true
  end

  it "returns true for new Threads" do
    Thread.new { Thread.current.report_on_exception }.value.should == true
  end

  it "returns whether the Thread will print a backtrace if it exits with an exception" do
    t = Thread.new { Thread.current.report_on_exception = true }
    t.join
    t.report_on_exception.should == true

    t = Thread.new { Thread.current.report_on_exception = false }
    t.join
    t.report_on_exception.should == false
  end
end

describe "Thread#report_on_exception=" do
  describe "when set to true" do
    it "prints a backtrace on $stderr if it terminates with an exception" do
      t = nil
      -> {
        t = Thread.new {
          Thread.current.report_on_exception = true
          raise RuntimeError, "Thread#report_on_exception specs"
        }
        Thread.pass while t.alive?
      }.should output("", /Thread.+terminated with exception.+Thread#report_on_exception specs/m)

      -> {
        t.join
      }.should raise_error(RuntimeError, "Thread#report_on_exception specs")
    end

    ruby_version_is "3.0" do
      it "prints a backtrace on $stderr in the regular backtrace order" do
        line_raise = __LINE__ + 2
        def foo
          raise RuntimeError, "Thread#report_on_exception specs backtrace order"
        end

        line_call_foo = __LINE__ + 5
        go = false
        t = Thread.new {
          Thread.current.report_on_exception = true
          Thread.pass until go
          foo
        }

        -> {
          go = true
          Thread.pass while t.alive?
        }.should output("", <<ERR)
#{t.inspect} terminated with exception (report_on_exception is true):
#{__FILE__}:#{line_raise}:in `foo': Thread#report_on_exception specs backtrace order (RuntimeError)
\tfrom #{__FILE__}:#{line_call_foo}:in `block (5 levels) in <top (required)>'
ERR

        -> {
          t.join
        }.should raise_error(RuntimeError, "Thread#report_on_exception specs backtrace order")
      end
    end

    it "prints the backtrace even if the thread was killed just after Thread#raise" do
      t = nil
      ready = false
      -> {
        t = Thread.new {
          Thread.current.report_on_exception = true
          ready = true
          sleep
        }

        Thread.pass until ready and t.stop?
        t.raise RuntimeError, "Thread#report_on_exception before kill spec"
        t.kill
        Thread.pass while t.alive?
      }.should output("", /Thread.+terminated with exception.+Thread#report_on_exception before kill spec/m)

      -> {
        t.join
      }.should raise_error(RuntimeError, "Thread#report_on_exception before kill spec")
    end
  end

  describe "when set to false" do
    it "lets the thread terminates silently with an exception" do
      t = nil
      -> {
        t = Thread.new {
          Thread.current.report_on_exception = false
          raise RuntimeError, "Thread#report_on_exception specs"
        }
        Thread.pass while t.alive?
      }.should output("", "")

      -> {
        t.join
      }.should raise_error(RuntimeError, "Thread#report_on_exception specs")
    end
  end

  describe "when used in conjunction with Thread#abort_on_exception" do
    it "first reports then send the exception back to the main Thread" do
      t = nil
      mutex = Mutex.new
      mutex.lock
      -> {
        t = Thread.new {
          Thread.current.abort_on_exception = true
          Thread.current.report_on_exception = true
          mutex.lock
          mutex.unlock
          raise RuntimeError, "Thread#report_on_exception specs"
        }

        -> {
          mutex.sleep(5)
        }.should raise_error(RuntimeError, "Thread#report_on_exception specs")
      }.should output("", /Thread.+terminated with exception.+Thread#report_on_exception specs/m)

      -> {
        t.join
      }.should raise_error(RuntimeError, "Thread#report_on_exception specs")
    end
  end
end
