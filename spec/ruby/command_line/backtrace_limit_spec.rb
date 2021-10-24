require_relative '../spec_helper'

ruby_version_is "3.0" do
  describe "The --backtrace-limit command line option" do
    it "limits top-level backtraces to a given number of entries" do
      file = fixture(__FILE__ , "backtrace.rb")
      out = ruby_exe(file, options: "--backtrace-limit=2", args: "top 2>&1", exit_status: 1)
      out = out.gsub(__dir__, '')

      out.should == <<-MSG
top
/fixtures/backtrace.rb:2:in `a': unhandled exception
\tfrom /fixtures/backtrace.rb:6:in `b'
\tfrom /fixtures/backtrace.rb:10:in `c'
\t ... 2 levels...
      MSG
    end

    it "affects Exception#full_message" do
      file = fixture(__FILE__ , "backtrace.rb")
      out = ruby_exe(file, options: "--backtrace-limit=2", args: "full_message 2>&1")
      out = out.gsub(__dir__, '')

      out.should == <<-MSG
full_message
/fixtures/backtrace.rb:2:in `a': unhandled exception
\tfrom /fixtures/backtrace.rb:6:in `b'
\tfrom /fixtures/backtrace.rb:10:in `c'
\t ... 2 levels...
      MSG
    end

    it "does not affect Exception#backtrace" do
      file = fixture(__FILE__ , "backtrace.rb")
      out = ruby_exe(file, options: "--backtrace-limit=2", args: "backtrace 2>&1")
      out = out.gsub(__dir__, '')

      out.should == <<-MSG
backtrace
/fixtures/backtrace.rb:2:in `a'
/fixtures/backtrace.rb:6:in `b'
/fixtures/backtrace.rb:10:in `c'
/fixtures/backtrace.rb:14:in `d'
/fixtures/backtrace.rb:29:in `<main>'
      MSG
    end
  end
end
