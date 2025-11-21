require_relative '../../../spec_helper'

describe "IO::Buffer#readonly?" do
  after :each do
    @buffer&.free
    @buffer = nil
  end

  context "with a buffer created with .new" do
    it "is false for an internal buffer" do
      @buffer = IO::Buffer.new(4, IO::Buffer::INTERNAL)
      @buffer.readonly?.should be_false
    end

    it "is false for a mapped buffer" do
      @buffer = IO::Buffer.new(4, IO::Buffer::MAPPED)
      @buffer.readonly?.should be_false
    end
  end

  context "with a file-backed buffer created with .map" do
    it "is false for a writable mapping" do
      File.open(__FILE__, "r+") do |file|
        @buffer = IO::Buffer.map(file)
        @buffer.readonly?.should be_false
      end
    end

    it "is true for a readonly mapping" do
      File.open(__FILE__, "r") do |file|
        @buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY)
        @buffer.readonly?.should be_true
      end
    end

    ruby_version_is "3.3" do
      it "is false for a private mapping" do
        File.open(__FILE__, "r") do |file|
          @buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::PRIVATE)
          @buffer.readonly?.should be_false
        end
      end
    end
  end

  context "with a String-backed buffer created with .for" do
    it "is true for a buffer created without a block" do
      @buffer = IO::Buffer.for(+"test")
      @buffer.readonly?.should be_true
    end

    it "is false for a buffer created with a block" do
      IO::Buffer.for(+"test") do |buffer|
        buffer.readonly?.should be_false
      end
    end

    it "is true for a buffer created with a block from a frozen string" do
      IO::Buffer.for(-"test") do |buffer|
        buffer.readonly?.should be_true
      end
    end
  end

  ruby_version_is "3.3" do
    context "with a String-backed buffer created with .string" do
      it "is false" do
        IO::Buffer.string(4) do |buffer|
          buffer.readonly?.should be_false
        end
      end
    end
  end

  # This seems to be the only flag propagated from the source buffer to the slice.
  context "with a slice of a buffer" do
    context "created with .new" do
      it "is false when slicing an internal buffer" do
        @buffer = IO::Buffer.new(4)
        @buffer.slice.readonly?.should be_false
      end

      it "is false when slicing a mapped buffer" do
        @buffer = IO::Buffer.new(4, IO::Buffer::MAPPED)
        @buffer.slice.readonly?.should be_false
      end
    end

    context "created with .map" do
      it "is false when slicing a read-write file-backed buffer" do
        File.open(__FILE__, "r+") do |file|
          @buffer = IO::Buffer.map(file)
          @buffer.slice.readonly?.should be_false
        end
      end

      it "is true when slicing a readonly file-backed buffer" do
        File.open(__FILE__, "r") do |file|
          @buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY)
          @buffer.slice.readonly?.should be_true
        end
      end

      ruby_version_is "3.3" do
        it "is false when slicing a private file-backed buffer" do
          File.open(__FILE__, "r") do |file|
            @buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::PRIVATE)
            @buffer.slice.readonly?.should be_false
          end
        end
      end
    end

    context "created with .for" do
      it "is true when slicing a buffer created without a block" do
        @buffer = IO::Buffer.for(+"test")
        @buffer.slice.readonly?.should be_true
      end

      it "is false when slicing a buffer created with a block" do
        IO::Buffer.for(+"test") do |buffer|
          buffer.slice.readonly?.should be_false
        end
      end

      it "is true when slicing a buffer created with a block from a frozen string" do
        IO::Buffer.for(-"test") do |buffer|
          buffer.slice.readonly?.should be_true
        end
      end
    end

    ruby_version_is "3.3" do
      context "created with .string" do
        it "is false" do
          IO::Buffer.string(4) do |buffer|
            buffer.slice.readonly?.should be_false
          end
        end
      end
    end
  end
end
