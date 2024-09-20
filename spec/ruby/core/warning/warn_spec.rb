require_relative '../../spec_helper'

describe "Warning.warn" do
  it "complains" do
    -> {
      Warning.warn("Chunky bacon!")
    }.should complain("Chunky bacon!")
  end

  it "does not add a newline" do
    ruby_exe("Warning.warn('test')", args: "2>&1").should == "test"
  end

  it "returns nil" do
    ruby_exe("p Warning.warn('test')", args: "2>&1").should == "testnil\n"
  end

  it "extends itself" do
    Warning.singleton_class.ancestors.should include(Warning)
  end

  it "has Warning as the method owner" do
    ruby_exe("p Warning.method(:warn).owner").should == "Warning\n"
  end

  it "can be overridden" do
    code = <<-RUBY
      $stdout.sync = true
      $stderr.sync = true
      def Warning.warn(msg)
        if msg.start_with?("A")
          puts msg.upcase
        else
          super
        end
      end
      Warning.warn("A warning!")
      Warning.warn("warning from stderr\n")
    RUBY
    ruby_exe(code, args: "2>&1").should == %Q[A WARNING!\nwarning from stderr\n]
  end

  it "is called by parser warnings" do
    Warning.should_receive(:warn)
    verbose = $VERBOSE
    $VERBOSE = false
    begin
      eval "{ key: :value, key: :value2 }"
    ensure
      $VERBOSE = verbose
    end
  end

  it "is called by Kernel.warn with nil category keyword" do
    Warning.should_receive(:warn).with("Chunky bacon!\n", category: nil)
    verbose = $VERBOSE
    $VERBOSE = false
    begin
      Kernel.warn("Chunky bacon!")
    ensure
      $VERBOSE = verbose
    end
  end

  it "is called by Kernel.warn with given category keyword converted to a symbol" do
    Warning.should_receive(:warn).with("Chunky bacon!\n", category: :deprecated)
    verbose = $VERBOSE
    $VERBOSE = false
    begin
      Kernel.warn("Chunky bacon!", category: "deprecated")
    ensure
      $VERBOSE = verbose
    end
  end

  it "warns when category is :deprecated and Warning[:deprecated] is true" do
    warn_deprecated = Warning[:deprecated]
    Warning[:deprecated] = true
    begin
      -> {
        Warning.warn("foo", category: :deprecated)
      }.should complain("foo")
    ensure
      Warning[:deprecated] = warn_deprecated
    end
  end

  it "warns when category is :experimental and Warning[:experimental] is true" do
    warn_experimental = Warning[:experimental]
    Warning[:experimental] = true
    begin
      -> {
        Warning.warn("foo", category: :experimental)
      }.should complain("foo")
    ensure
      Warning[:experimental] = warn_experimental
    end
  end

  it "doesn't print message when category is :deprecated but Warning[:deprecated] is false" do
    warn_deprecated = Warning[:deprecated]
    Warning[:deprecated] = false
    begin
      -> {
        Warning.warn("foo", category: :deprecated)
      }.should_not complain
    ensure
      Warning[:deprecated] = warn_deprecated
    end
  end

  it "doesn't print message when category is :experimental but Warning[:experimental] is false" do
    warn_experimental = Warning[:experimental]
    Warning[:experimental] = false
    begin
      -> {
        Warning.warn("foo", category: :experimental)
      }.should_not complain
    ensure
      Warning[:experimental] = warn_experimental
    end
  end

  ruby_bug '#19530', ''...'3.4' do
    it "isn't called by Kernel.warn when category is :deprecated but Warning[:deprecated] is false" do
      warn_deprecated = Warning[:deprecated]
      begin
        Warning[:deprecated] = false
        Warning.should_not_receive(:warn)
        Kernel.warn("foo", category: :deprecated)
      ensure
        Warning[:deprecated] = warn_deprecated
      end
    end

    it "isn't called by Kernel.warn when category is :experimental but Warning[:experimental] is false" do
      warn_experimental = Warning[:experimental]
      begin
        Warning[:experimental] = false
        Warning.should_not_receive(:warn)
        Kernel.warn("foo", category: :experimental)
      ensure
        Warning[:experimental] = warn_experimental
      end
    end
  end

  it "prints the message when VERBOSE is false" do
    -> { Warning.warn("foo") }.should complain("foo")
  end

  it "prints the message when VERBOSE is nil" do
    -> { Warning.warn("foo") }.should complain("foo", verbose: nil)
  end

  it "prints the message when VERBOSE is true" do
    -> { Warning.warn("foo") }.should complain("foo", verbose: true)
  end
end
