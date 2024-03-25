require_relative '../../spec_helper'

describe "An Exception reaching the top level" do
  it "is printed on STDERR" do
    ruby_exe('raise "foo"', args: "2>&1", exit_status: 1).should =~ /in [`']<main>': foo \(RuntimeError\)/
  end

  it "the Exception#cause is printed to STDERR with backtraces" do
    code = <<-RUBY
    def raise_cause
      raise "the cause"
    end
    def raise_wrapped
      raise "wrapped"
    end
    begin
      raise_cause
    rescue
      raise_wrapped
    end
    RUBY
    lines = ruby_exe(code, args: "2>&1", exit_status: 1).lines
    lines.map! { |l| l.chomp[/:(in.+)/, 1] }
    lines.size.should == 5
    lines[0].should =~ /\Ain [`'](?:Object#)?raise_wrapped': wrapped \(RuntimeError\)\z/
    lines[1].should =~ /\Ain [`'](?:rescue in )?<main>'\z/
    lines[2].should =~ /\Ain [`']<main>'\z/
    lines[3].should =~ /\Ain [`'](?:Object#)?raise_cause': the cause \(RuntimeError\)\z/
    lines[4].should =~ /\Ain [`']<main>'\z/
  end

  describe "with a custom backtrace" do
    it "is printed on STDERR" do
      code = <<-RUBY
      raise RuntimeError, "foo", [
        "/dir/foo.rb:10:in `raising'",
        "/dir/bar.rb:20:in `caller'",
      ]
      RUBY
      ruby_exe(code, args: "2>&1", exit_status: 1).should == <<-EOS
/dir/foo.rb:10:in `raising': foo (RuntimeError)
\tfrom /dir/bar.rb:20:in `caller'
      EOS
    end
  end

  describe "kills all threads and fibers, ensure clauses are only run for threads current fibers, not for suspended fibers" do
    it "with ensure on the root fiber" do
      file = fixture(__FILE__, "thread_fiber_ensure.rb")
      ruby_exe(file, args: "2>&1", exit_status: 0).should == "current fiber ensure\n"
    end

    it "with ensure on non-root fiber" do
      file = fixture(__FILE__, "thread_fiber_ensure_non_root_fiber.rb")
      ruby_exe(file, args: "2>&1", exit_status: 0).should == "current fiber ensure\n"
    end
  end
end
