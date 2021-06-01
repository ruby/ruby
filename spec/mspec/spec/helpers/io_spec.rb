require 'spec_helper'
require 'mspec/guards'
require 'mspec/helpers'

RSpec.describe IOStub do
  before :each do
    @out = IOStub.new
    @sep = $\
  end

  after :each do
    $\ = @sep
  end

  it "provides a write method" do
    @out.write "this"
    expect(@out).to eq("this")
  end

  it "concatenates the arguments sent to write" do
    @out.write "flim ", "flam"
    expect(@out).to eq("flim flam")
  end

  it "provides a print method that appends the default separator" do
    $\ = " [newline] "
    @out.print "hello"
    @out.print "world"
    expect(@out).to eq("hello [newline] world [newline] ")
  end

  it "provides a puts method that appends the default separator" do
    @out.puts "hello", 1, 2, 3
    expect(@out).to eq("hello\n1\n2\n3\n")
  end

  it "provides a puts method that appends separator if argument not given" do
    @out.puts
    expect(@out).to eq("\n")
  end

  it "provides a printf method" do
    @out.printf "%-10s, %03d, %2.1f", "test", 42, 4.2
    expect(@out).to eq("test      , 042, 4.2")
  end

  it "provides a flush method that does nothing and returns self" do
    expect(@out.flush).to eq(@out)
  end
end

RSpec.describe Object, "#new_fd" do
  before :each do
    @name = tmp("io_specs")
    @io = nil
  end

  after :each do
    @io.close if @io and not @io.closed?
    rm_r @name
  end

  it "returns an Integer that can be used to create an IO instance" do
    fd = new_fd @name
    expect(fd).to be_kind_of(Integer)

    @io = IO.new fd, 'w:utf-8'
    @io.sync = true
    @io.print "io data"

    expect(IO.read(@name)).to eq("io data")
  end

  it "accepts an options Hash" do
    allow(FeatureGuard).to receive(:enabled?).and_return(true)
    fd = new_fd @name, { :mode => 'w:utf-8' }
    expect(fd).to be_kind_of(Integer)

    @io = IO.new fd, 'w:utf-8'
    @io.sync = true
    @io.print "io data"

    expect(IO.read(@name)).to eq("io data")
  end

  it "raises an ArgumentError if the options Hash does not include :mode" do
    allow(FeatureGuard).to receive(:enabled?).and_return(true)
    expect { new_fd @name, { :encoding => "utf-8" } }.to raise_error(ArgumentError)
  end
end

RSpec.describe Object, "#new_io" do
  before :each do
    @name = tmp("io_specs.txt")
  end

  after :each do
    @io.close if @io and !@io.closed?
    rm_r @name
  end

  it "returns a File instance" do
    @io = new_io @name
    expect(@io).to be_an_instance_of(File)
  end

  it "opens the IO for reading if passed 'r'" do
    touch(@name) { |f| f.print "io data" }
    @io = new_io @name, "r"
    expect(@io.read).to eq("io data")
    expect { @io.puts "more data" }.to raise_error(IOError)
  end

  it "opens the IO for writing if passed 'w'" do
    @io = new_io @name, "w"
    @io.sync = true

    @io.print "io data"
    expect(IO.read(@name)).to eq("io data")
  end

  it "opens the IO for reading if passed { :mode => 'r' }" do
    touch(@name) { |f| f.print "io data" }
    @io = new_io @name, { :mode => "r" }
    expect(@io.read).to eq("io data")
    expect { @io.puts "more data" }.to raise_error(IOError)
  end

  it "opens the IO for writing if passed { :mode => 'w' }" do
    @io = new_io @name, { :mode => "w" }
    @io.sync = true

    @io.print "io data"
    expect(IO.read(@name)).to eq("io data")
  end
end
