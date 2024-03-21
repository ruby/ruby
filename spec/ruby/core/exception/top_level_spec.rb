require_relative '../../spec_helper'

describe "An Exception reaching the top level" do
  it "is printed on STDERR" do
    ruby_exe('raise "foo"', args: "2>&1", exit_status: 1).should =~ /in [`']<main>': foo \(RuntimeError\)/
  end

  it "the Exception#cause is printed to STDERR with backtraces" do
    code = <<-RUBY
    def raise_cause
      raise "the cause" # 2
    end
    def raise_wrapped
      raise "wrapped" # 5
    end
    begin
      raise_cause # 8
    rescue
      raise_wrapped # 10
    end
    RUBY
    lines = ruby_exe(code, args: "2>&1", exit_status: 1).lines

    lines.map! { |l| l.chomp[/:(\d+:in.+)/, 1] }
    lines[0].should =~ /\A5:in [`'](?:Object#)?raise_wrapped': wrapped \(RuntimeError\)\z/
    if lines[1].include? 'rescue in'
      # CRuby < 3.4 has an extra 'rescue in' backtrace entry
      lines[1].should =~ /\A10:in [`']rescue in <main>'\z/
      lines.delete_at 1
      lines[1].should =~ /\A7:in [`']<main>'\z/
    else
      lines[1].should =~ /\A10:in [`']<main>'\z/
    end
    lines[2].should =~ /\A2:in [`'](?:Object#)?raise_cause': the cause \(RuntimeError\)\z/
    lines[3].should =~ /\A8:in [`']<main>'\z/
    lines.size.should == 4
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
