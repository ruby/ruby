require_relative '../../spec_helper'
require_relative 'fixtures/classes'

# NOTE: most specs are in sprintf_spec.rb, this is just an alias
describe "Kernel#format" do
  it "is a private method" do
    Kernel.should have_private_instance_method(:format)
  end
end

describe "Kernel.format" do
  it "is accessible as a module function" do
    Kernel.format("%s", "hello").should == "hello"
  end

  describe "when $VERBOSE is true" do
    it "warns if too many arguments are passed" do
      code = <<~RUBY
        $VERBOSE = true
        format("test", 1)
      RUBY

      ruby_exe(code, args: "2>&1").should include("warning: too many arguments for format string")
    end

    it "does not warns if too many keyword arguments are passed" do
      code = <<~RUBY
        $VERBOSE = true
        format("test %{test}", test: 1, unused: 2)
      RUBY

      ruby_exe(code, args: "2>&1").should_not include("warning")
    end

    ruby_bug "#20593", ""..."3.4" do
      it "doesn't warns if keyword arguments are passed and none are used" do
        code = <<~RUBY
          $VERBOSE = true
          format("test", test: 1)
          format("test", {})
        RUBY

        ruby_exe(code, args: "2>&1").should_not include("warning")
      end
    end
  end
end
