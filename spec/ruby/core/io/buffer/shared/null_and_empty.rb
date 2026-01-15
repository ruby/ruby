describe :io_buffer_null_and_empty, shared: true do
  it "is false for a buffer with size > 0" do
    @buffer = IO::Buffer.new(1)
    @buffer.send(@method).should be_false
  end

  it "is false for a slice with length > 0" do
    @buffer = IO::Buffer.new(4)
    @buffer.slice(1, 2).send(@method).should be_false
  end

  it "is false for a file-mapped buffer" do
    File.open(__FILE__, "rb") do |file|
      @buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY)
      @buffer.send(@method).should be_false
    end
  end

  it "is false for a non-empty String-backed buffer created with .for" do
    @buffer = IO::Buffer.for("test")
    @buffer.send(@method).should be_false
  end

  ruby_version_is "3.3" do
    it "is false for a non-empty String-backed buffer created with .string" do
      IO::Buffer.string(4) do |buffer|
        buffer.send(@method).should be_false
      end
    end
  end

  it "is true for a 0-sized buffer" do
    @buffer = IO::Buffer.new(0)
    @buffer.send(@method).should be_true
  end

  it "is true for a slice of a 0-sized buffer" do
    @buffer = IO::Buffer.new(0)
    @buffer.slice(0, 0).send(@method).should be_true
  end

  it "is true for a freed buffer" do
    @buffer = IO::Buffer.new(1)
    @buffer.free
    @buffer.send(@method).should be_true
  end

  it "is true for a buffer resized to 0" do
    @buffer = IO::Buffer.new(1)
    @buffer.resize(0)
    @buffer.send(@method).should be_true
  end

  it "is true for a buffer whose memory was transferred" do
    buffer = IO::Buffer.new(1)
    @buffer = buffer.transfer
    buffer.send(@method).should be_true
  end
end
