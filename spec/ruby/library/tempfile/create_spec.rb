require_relative '../../spec_helper'
require 'tempfile'

describe "Tempfile.create" do
  after :each do
    if @tempfile
      @tempfile.close
      File.unlink(@tempfile.path) if File.file?(@tempfile.path)
    end
  end

  it "returns a new, open regular File instance placed in tmpdir" do
    @tempfile = Tempfile.create
    # Unlike Tempfile.open this returns a true File,
    # but `.should be_an_instance_of(File)` would be true either way.
    @tempfile.instance_of?(File).should be_true

    @tempfile.should_not.closed?
    File.file?(@tempfile.path).should be_true

    @tempfile.path.should.start_with?(Dir.tmpdir)
    @tempfile.path.should_not == "#{Dir.tmpdir}/"
  end

  it "returns file in w+ mode" do
    @tempfile = Tempfile.create
    @tempfile << "Test!\nMore test!"
    @tempfile.rewind
    @tempfile.read.should == "Test!\nMore test!"

    # Not "a+" mode, which would write at the end of the file.
    @tempfile.rewind
    @tempfile.print "Trust"
    @tempfile.rewind
    @tempfile.read.should == "Trust\nMore test!"
  end

  platform_is_not :windows do
    it "returns a private, readable and writable file" do
      @tempfile = Tempfile.create
      stat = @tempfile.stat
      stat.should.readable?
      stat.should.writable?
      stat.should_not.executable?
      stat.should_not.world_readable?
      stat.should_not.world_writable?
    end
  end

  platform_is :windows do
    it "returns a public, readable and writable file" do
      @tempfile = Tempfile.create
      stat = @tempfile.stat
      stat.should.readable?
      stat.should.writable?
      stat.should_not.executable?
      stat.should.world_readable?
      stat.should.world_writable?
    end
  end

  context "when called with a block" do
    it "returns the value of the block" do
      value = Tempfile.create do |tempfile|
        tempfile << "Test!"
        "return"
      end
      value.should == "return"
    end

    it "closes and unlinks file after block execution" do
      Tempfile.create do |tempfile|
        @tempfile = tempfile
        @tempfile.should_not.closed?
        File.exist?(@tempfile.path).should be_true
      end

      @tempfile.should.closed?
      File.exist?(@tempfile.path).should be_false
    end
  end

  context "when called with a single positional argument" do
    it "uses a String as a prefix for the filename" do
      @tempfile = Tempfile.create("create_spec")
      @tempfile.path.should.start_with?("#{Dir.tmpdir}/create_spec")
      @tempfile.path.should_not == "#{Dir.tmpdir}/create_spec"
    end

    it "uses an array of one String as a prefix for the filename" do
      @tempfile = Tempfile.create(["create_spec"])
      @tempfile.path.should.start_with?("#{Dir.tmpdir}/create_spec")
      @tempfile.path.should_not == "#{Dir.tmpdir}/create_spec"
    end

    it "uses an array of two Strings as a prefix and suffix for the filename" do
      @tempfile = Tempfile.create(["create_spec", ".temp"])
      @tempfile.path.should.start_with?("#{Dir.tmpdir}/create_spec")
      @tempfile.path.should.end_with?(".temp")
    end

    it "ignores excessive array elements after the first two" do
      @tempfile = Tempfile.create(["create_spec", ".temp", :".txt"])
      @tempfile.path.should.start_with?("#{Dir.tmpdir}/create_spec")
      @tempfile.path.should.end_with?(".temp")
    end

    it "raises ArgumentError if passed something else than a String or an array of Strings" do
      -> { Tempfile.create(:create_spec) }.should raise_error(ArgumentError, "unexpected prefix: :create_spec")
      -> { Tempfile.create([:create_spec]) }.should raise_error(ArgumentError, "unexpected prefix: :create_spec")
      -> { Tempfile.create(["create_spec", :temp]) }.should raise_error(ArgumentError, "unexpected suffix: :temp")
    end
  end

  context "when called with a second positional argument" do
    it "uses it as a directory for the tempfile" do
      @tempfile = Tempfile.create("create_spec", "./")
      @tempfile.path.should.start_with?("./create_spec")
    end

    it "raises TypeError if argument can not be converted to a String" do
      -> { Tempfile.create("create_spec", :temp) }.should raise_error(TypeError, "no implicit conversion of Symbol into String")
    end
  end

  context "when called with a mode option" do
    it "ORs it with the default mode, forcing it to be readable and writable" do
      @tempfile = Tempfile.create(mode: File::RDONLY)
      @tempfile.puts "test"
      @tempfile.rewind
      @tempfile.read.should == "test\n"
    end

    it "raises NoMethodError if passed a String mode" do
      -> { Tempfile.create(mode: "wb") }.should raise_error(NoMethodError, /undefined method ['`]|' for .+String/)
    end
  end

  ruby_version_is "3.4" do
    context "when called with anonymous: true" do
      it "returns an already unlinked File without a proper path" do
        @tempfile = Tempfile.create(anonymous: true)
        @tempfile.should_not.closed?
        @tempfile.path.should == "#{Dir.tmpdir}/"
        File.file?(@tempfile.path).should be_false
      end

      it "unlinks file before calling the block" do
        Tempfile.create(anonymous: true) do |tempfile|
          @tempfile = tempfile
          @tempfile.should_not.closed?
          @tempfile.path.should == "#{Dir.tmpdir}/"
          File.file?(@tempfile.path).should be_false
        end
        @tempfile.should.closed?
      end
    end

    context "when called with anonymous: false" do
      it "returns a usual File with a path" do
        @tempfile = Tempfile.create(anonymous: false)
        @tempfile.should_not.closed?
        @tempfile.path.should.start_with?(Dir.tmpdir)
        File.file?(@tempfile.path).should be_true
      end
    end
  end

  context "when called with other options" do
    it "passes them along to File.open" do
      @tempfile = Tempfile.create(encoding: "IBM037:IBM037", binmode: true)
      @tempfile.external_encoding.should == Encoding.find("IBM037")
      @tempfile.binmode?.should be_true
    end
  end
end
