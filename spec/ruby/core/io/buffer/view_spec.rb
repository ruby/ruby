require_relative '../../../spec_helper'

ruby_version_is "4.1" do
  describe :io_buffer_view_access, shared: true do
    before :each do
      @storage = IO::Buffer.new(8)
      @storage.set_string("abcdefgh")
      @view = @method == :buffer ? @storage : @storage.slice
      @other = nil
    end

    after :each do
      @other&.free
      @storage.free
    end

    it "reads and writes through the common byte-access interface" do
      @view.get_string.should == "abcdefgh"
      @view.set_value(:U8, 0, 65)
      @view.get_values([:U8, :U8], 0).should == [65, 98]
      @storage.get_string.should == "Abcdefgh"
    end

    it "accepts another Slice as a copy source and comparison operand" do
      @other = IO::Buffer.for("XABCDEFGHY")
      source = @other.slice(1, 8)
      @view.copy(source).should == 8
      @view.get_string.should == "ABCDEFGH"
      (@view <=> source).should == 0
    end

    it "accepts a Slice as a bitwise mask" do
      @other = IO::Buffer.for("x x")
      @view.xor!(@other.slice(1, 1)).should.equal?(@view)
      @view.get_string.should == "ABCDEFGH"
    end

    it "locks the backing allocation for the scope" do
      @view.locked do
        @view.should.locked?
        @storage.should.locked?
        -> { @storage.free }.should.raise(IO::Buffer::LockedError)
      end
      @view.should_not.locked?
      @storage.should_not.locked?
    end

    it "can write its bytes directly to an IO" do
      IO.pipe do |reader, writer|
        @view.write(writer).should == 8
        reader.read(8).should == "abcdefgh"
      end
    end

    it "can read bytes directly from an IO" do
      IO.pipe do |reader, writer|
        writer.write("ABCDEFGH")
        @view.read(reader).should == 8
        @storage.get_string.should == "ABCDEFGH"
      end
    end
  end

  describe "IO::Buffer byte-access protocol" do
    it_behaves_like :io_buffer_view_access, :buffer
  end

  describe "IO::Buffer::Slice byte-access protocol" do
    it_behaves_like :io_buffer_view_access, :slice
  end

  describe "IO::Buffer and IO::Buffer::Slice" do
    before :each do
      @buffer = IO::Buffer.new(8)
      @buffer.set_string("abcdefgh")
      @slice = @buffer.slice(1, 4)
    end

    after :each do
      @buffer.free
    end

    it "are distinct types with a private, non-instantiable common superclass" do
      @slice.should.is_a?(IO::Buffer::Slice)
      @slice.is_a?(IO::Buffer).should == false
      IO::Buffer.superclass.should.equal?(IO::Buffer::Slice.superclass)
      -> { IO::Buffer::View }.should.raise(NameError)
      -> { IO::Buffer.superclass.new }.should.raise(TypeError)
    end

    it "exposes allocation predicates and lifecycle methods only on Buffer" do
      [:internal?, :external?, :mapped?, :shared?, :private?, :free, :transfer].each do |method|
        @buffer.respond_to?(method).should == true
        @slice.respond_to?(method).should == false
      end
      [:locked?, :locked, :valid?, :null?, :empty?, :readonly?, :size, :source].each do |method|
        @buffer.respond_to?(method).should == true
        @slice.respond_to?(method).should == true
      end
    end

    it "constructs a Slice relative to an explicit parent" do
      child = IO::Buffer::Slice.new(@slice, 1, 2)
      child.source.should.equal?(@slice)
      child.get_string.should == "cd"
      -> { IO::Buffer::Slice.new(@slice, 1, 4) }.should.raise(ArgumentError)
    end

    it "duplicates a Slice's view without copying the bytes" do
      copy = @slice.dup
      copy.class.should == IO::Buffer::Slice
      copy.source.should.equal?(@buffer)
      copy.advance(1)
      copy.get_string.should == "cde"
      @slice.get_string.should == "bcde"
      copy.set_string("XYZ")
      @slice.get_string.should == "bXYZ"
    end

    it "duplicates Buffer storage independently" do
      copy = @buffer.dup
      begin
        copy.class.should == IO::Buffer
        copy.source.should == nil
        copy.set_string("ABCDEFGH")
        @buffer.get_string.should == "abcdefgh"
      ensure
        copy.free
      end
    end

    it "does not detach or reallocate a Slice when resized to zero" do
      @slice.resize(0)
      @slice.source.should.equal?(@buffer)
      @slice.resize(4)
      @slice.get_string.should == "bcde"
      -> { @slice.resize(8) }.should.raise(ArgumentError)
    end

    it "treats free as idempotent on an ordinary Buffer" do
      @buffer.free.should.equal?(@buffer)
      @buffer.free.should.equal?(@buffer)
      @buffer.should.null?
    end
  end
end
