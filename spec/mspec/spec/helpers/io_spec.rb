require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'

describe IOStub do
  before :each do
    @out = IOStub.new
    @sep = $\
  end

  after :each do
    $\ = @sep
  end

  it "provides a write method" do
    @out.write "this"
    @out.should == "this"
  end

  it "concatenates the arguments sent to write" do
    @out.write "flim ", "flam"
    @out.should == "flim flam"
  end

  it "provides a print method that appends the default separator" do
    $\ = " [newline] "
    @out.print "hello"
    @out.print "world"
    @out.should == "hello [newline] world [newline] "
  end

  it "provides a puts method that appends the default separator" do
    @out.puts "hello", 1, 2, 3
    @out.should == "hello\n1\n2\n3\n"
  end

  it "provides a puts method that appends separator if argument not given" do
    @out.puts
    @out.should == "\n"
  end

  it "provides a printf method" do
    @out.printf "%-10s, %03d, %2.1f", "test", 42, 4.2
    @out.should == "test      , 042, 4.2"
  end

  it "provides a flush method that does nothing and returns self" do
    @out.flush.should == @out
  end
end

describe Object, "#new_fd" do
  before :each do
    @name = tmp("io_specs")
    @io = nil
  end

  after :each do
    @io.close if @io and not @io.closed?
    rm_r @name
  end

  it "returns a Integer that can be used to create an IO instance" do
    fd = new_fd @name
    fd.should be_kind_of(Integer)

    @io = IO.new fd, fmode('w:utf-8')
    @io.sync = true
    @io.print "io data"

    IO.read(@name).should == "io data"
  end

  it "accepts an options Hash" do
    FeatureGuard.stub(:enabled?).and_return(true)
    fd = new_fd @name, { :mode => 'w:utf-8' }
    fd.should be_kind_of(Integer)

    @io = IO.new fd, fmode('w:utf-8')
    @io.sync = true
    @io.print "io data"

    IO.read(@name).should == "io data"
  end

  it "raises an ArgumentError if the options Hash does not include :mode" do
    FeatureGuard.stub(:enabled?).and_return(true)
    lambda { new_fd @name, { :encoding => "utf-8" } }.should raise_error(ArgumentError)
  end
end

describe Object, "#new_io" do
  before :each do
    @name = tmp("io_specs.txt")
  end

  after :each do
    @io.close if @io and !@io.closed?
    rm_r @name
  end

  it "returns an IO instance" do
    @io = new_io @name
    @io.should be_an_instance_of(IO)
  end

  it "opens the IO for reading if passed 'r'" do
    touch(@name) { |f| f.print "io data" }
    @io = new_io @name, "r"
    @io.read.should == "io data"
    lambda { @io.puts "more data" }.should raise_error(IOError)
  end

  it "opens the IO for writing if passed 'w'" do
    @io = new_io @name, "w"
    @io.sync = true

    @io.print "io data"
    IO.read(@name).should == "io data"
  end

  it "opens the IO for reading if passed { :mode => 'r' }" do
    touch(@name) { |f| f.print "io data" }
    @io = new_io @name, { :mode => "r" }
    @io.read.should == "io data"
    lambda { @io.puts "more data" }.should raise_error(IOError)
  end

  it "opens the IO for writing if passed { :mode => 'w' }" do
    @io = new_io @name, { :mode => "w" }
    @io.sync = true

    @io.print "io data"
    IO.read(@name).should == "io data"
  end
end

describe Object, "#fmode" do
  it "returns the argument unmodified if :encoding feature is enabled" do
    FeatureGuard.should_receive(:enabled?).with(:encoding).and_return(true)
    fmode("rb:binary:utf-8").should == "rb:binary:utf-8"
  end

  it "returns only the file access mode if :encoding feature is not enabled" do
    FeatureGuard.should_receive(:enabled?).with(:encoding).and_return(false)
    fmode("rb:binary:utf-8").should == "rb"
  end
end

describe Object, "#options_or_mode" do
  describe "if passed a Hash" do
    it "returns a mode string if :encoding feature is not enabled" do
      FeatureGuard.should_receive(:enabled?).with(:encoding).twice.and_return(false)
      options_or_mode(:mode => "rb:binary").should == "rb"
    end

    it "returns a Hash if :encoding feature is enabled" do
      FeatureGuard.should_receive(:enabled?).with(:encoding).and_return(true)
      options_or_mode(:mode => "rb:utf-8").should == { :mode => "rb:utf-8" }
    end
  end

  describe "if passed a String" do
    it "returns only the file access mode if :encoding feature is not enabled" do
      FeatureGuard.should_receive(:enabled?).with(:encoding).and_return(false)
      options_or_mode("rb:binary:utf-8").should == "rb"
    end

    it "returns the argument unmodified if :encoding feature is enabled" do
      FeatureGuard.should_receive(:enabled?).with(:encoding).and_return(true)
      options_or_mode("rb:binary:utf-8").should == "rb:binary:utf-8"
    end
  end
end
