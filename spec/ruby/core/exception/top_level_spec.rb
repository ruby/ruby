require_relative '../../spec_helper'

describe "An Exception reaching the top level" do
  it "is printed on STDERR" do
    ruby_exe('raise "foo"', args: "2>&1").should.include?("in `<main>': foo (RuntimeError)")
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
