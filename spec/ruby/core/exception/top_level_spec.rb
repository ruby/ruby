require_relative '../../spec_helper'

describe "An Exception reaching the top level" do
  it "is printed on STDERR" do
    ruby_exe('raise "foo"', args: "2>&1").should.include?("in `<main>': foo (RuntimeError)")
  end

  ruby_version_is "2.6" do
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
      lines = ruby_exe(code, args: "2>&1").lines
      lines.reject! { |l| l.include?('rescue in') }
      lines.map! { |l| l.chomp[/:(in.+)/, 1] }
      lines.should == ["in `raise_wrapped': wrapped (RuntimeError)",
                       "in `<main>'",
                       "in `raise_cause': the cause (RuntimeError)",
                       "in `<main>'"]
    end
  end

  describe "with a custom backtrace" do
    it "is printed on STDERR" do
      code = <<-RUBY
      raise RuntimeError, "foo", [
        "/dir/foo.rb:10:in `raising'",
        "/dir/bar.rb:20:in `caller'",
      ]
      RUBY
      ruby_exe(code, args: "2>&1").should == <<-EOS
/dir/foo.rb:10:in `raising': foo (RuntimeError)
\tfrom /dir/bar.rb:20:in `caller'
      EOS
    end
  end
end
