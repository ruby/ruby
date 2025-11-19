require_relative '../../../spec_helper'

ruby_version_is "3.3" do
  describe "IO::Buffer#private?" do
    after :each do
      @buffer&.free
      @buffer = nil
    end

    context "with a buffer created with .new" do
      it "is false for an internal buffer" do
        @buffer = IO::Buffer.new(4, IO::Buffer::INTERNAL)
        @buffer.private?.should be_false
      end

      it "is false for a mapped buffer" do
        @buffer = IO::Buffer.new(4, IO::Buffer::MAPPED)
        @buffer.private?.should be_false
      end
    end

    context "with a file-backed buffer created with .map" do
      it "is false for a regular mapping" do
        File.open(__FILE__, "r") do |file|
          @buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY)
          @buffer.private?.should be_false
        end
      end

      it "is true for a private mapping" do
        File.open(__FILE__, "r") do |file|
          @buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY | IO::Buffer::PRIVATE)
          @buffer.private?.should be_true
        end
      end
    end

    context "with a String-backed buffer created with .for" do
      it "is false for a buffer created without a block" do
        @buffer = IO::Buffer.for("test")
        @buffer.private?.should be_false
      end

      it "is false for a buffer created with a block" do
        IO::Buffer.for(+"test") do |buffer|
          buffer.private?.should be_false
        end
      end
    end

    context "with a String-backed buffer created with .string" do
      it "is false" do
        IO::Buffer.string(4) do |buffer|
          buffer.private?.should be_false
        end
      end
    end

    # Always false for slices
    context "with a slice of a buffer" do
      context "created with .new" do
        it "is false when slicing an internal buffer" do
          @buffer = IO::Buffer.new(4)
          @buffer.slice.private?.should be_false
        end

        it "is false when slicing a mapped buffer" do
          @buffer = IO::Buffer.new(4, IO::Buffer::MAPPED)
          @buffer.slice.private?.should be_false
        end
      end

      context "created with .map" do
        it "is false when slicing a regular file-backed buffer" do
          File.open(__FILE__, "r") do |file|
            @buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY)
            @buffer.slice.private?.should be_false
          end
        end

        it "is false when slicing a private file-backed buffer" do
          File.open(__FILE__, "r") do |file|
            @buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY | IO::Buffer::PRIVATE)
            @buffer.slice.private?.should be_false
          end
        end
      end

      context "created with .for" do
        it "is false when slicing a buffer created without a block" do
          @buffer = IO::Buffer.for("test")
          @buffer.slice.private?.should be_false
        end

        it "is false when slicing a buffer created with a block" do
          IO::Buffer.for(+"test") do |buffer|
            buffer.slice.private?.should be_false
          end
        end
      end

      context "created with .string" do
        it "is false" do
          IO::Buffer.string(4) do |buffer|
            buffer.slice.private?.should be_false
          end
        end
      end
    end
  end
end
