require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel.at_exit" do
  it "is a private method" do
    Kernel.should have_private_instance_method(:at_exit)
  end

  it "runs after all other code" do
    ruby_exe("at_exit {print 5}; print 6").should == "65"
  end

  it "runs in reverse order of registration" do
    code = "at_exit {print 4};at_exit {print 5}; print 6; at_exit {print 7}"
    ruby_exe(code).should == "6754"
  end

  it "allows calling exit inside at_exit handler" do
    code = "at_exit {print 3}; at_exit {print 4; exit; print 5}; at_exit {print 6}"
    ruby_exe(code).should == "643"
  end

  it "gives access to the last raised exception" do
    code = <<-EOC
      at_exit do
        puts "The exception matches: \#{$! == $exception} (message=\#{$!.message})"
      end

      begin
        raise "foo"
      rescue => $exception
        raise
      end
    EOC

    result = ruby_exe(code, args: "2>&1", exit_status: 1)
    result.lines.should.include?("The exception matches: true (message=foo)\n")
  end

  it "both exceptions in at_exit and in the main script are printed" do
    code = 'at_exit { raise "at_exit_error" }; raise "main_script_error"'
    result = ruby_exe(code, args: "2>&1", exit_status: 1)
    result.should.include?('at_exit_error (RuntimeError)')
    result.should.include?('main_script_error (RuntimeError)')
  end

  it "decides the exit status if both at_exit and the main script raise SystemExit" do
    ruby_exe('at_exit { exit 43 }; exit 42', args: "2>&1", exit_status: 43)
    $?.exitstatus.should == 43
  end

  it "runs all at_exit even if some raise exceptions" do
    code = 'at_exit { STDERR.puts "last" }; at_exit { exit 43 }; at_exit { STDERR.puts "first" }; exit 42'
    result = ruby_exe(code, args: "2>&1", exit_status: 43)
    result.should == "first\nlast\n"
    $?.exitstatus.should == 43
  end

  it "runs at_exit handlers even if the main script fails to parse" do
    script = fixture(__FILE__, "at_exit.rb")
    result = ruby_exe('{', options: "-r#{script}", args: "2>&1", exit_status: 1)
    $?.should_not.success?
    result.should.include?("at_exit ran\n")
    result.should.include?("syntax error")
  end
end

describe "Kernel#at_exit" do
  it "needs to be reviewed for spec completeness"
end
