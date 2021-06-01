require_relative '../spec_helper'

describe "The -e command line option" do
  it "evaluates the given string" do
    ruby_exe("puts 'foo'").chomp.should == "foo"
  end

  it "joins multiple strings with newlines" do
    ruby_exe(nil, args: %Q{-e "puts 'hello" -e "world'" 2>&1}).chomp.should == "hello\nworld"
  end

  it "uses 'main' as self" do
    ruby_exe("puts self", escape: false).chomp.should == "main"
  end

  it "uses '-e' as file" do
    ruby_exe("puts __FILE__", escape: false).chomp.should == "-e"
  end

  it "uses '-e' in $0" do
    system(*ruby_exe, '-e', 'exit $0 == "-e"').should == true
  end

  #needs to test return => LocalJumpError

  describe "with -n and an Integer range" do
    before :each do
      @script = "-ne 'print if %s' #{fixture(__FILE__, "conditional_range.txt")}"
    end

    it "mimics an awk conditional by comparing an inclusive-end range with $." do
      ruby_exe(nil, args: (@script % "2..3")).should == "2\n3\n"
      ruby_exe(nil, args: (@script % "2..2")).should == "2\n"
    end

    it "mimics a sed conditional by comparing an exclusive-end range with $." do
      ruby_exe(nil, args: (@script % "2...3")).should == "2\n3\n"
      ruby_exe(nil, args: (@script % "2...2")).should == "2\n3\n4\n5\n"
    end
  end
end
