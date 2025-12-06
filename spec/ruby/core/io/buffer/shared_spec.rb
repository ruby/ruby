require_relative '../../../spec_helper'

describe "IO::Buffer#shared?" do
  after :each do
    @buffer&.free
    @buffer = nil
  end

  context "with a buffer created with .new" do
    it "is false for an internal buffer" do
      @buffer = IO::Buffer.new(4, IO::Buffer::INTERNAL)
      @buffer.shared?.should be_false
    end

    it "is false for a mapped buffer" do
      @buffer = IO::Buffer.new(4, IO::Buffer::MAPPED)
      @buffer.shared?.should be_false
    end
  end

  context "with a file-backed buffer created with .map" do
    it "is true for a regular mapping" do
      File.open(__FILE__, "r") do |file|
        @buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY)
        @buffer.shared?.should be_true
      end
    end

    ruby_version_is "3.3" do
      it "is false for a private mapping" do
        File.open(__FILE__, "r") do |file|
          @buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY | IO::Buffer::PRIVATE)
          @buffer.shared?.should be_false
        end
      end
    end
  end

  context "with a String-backed buffer created with .for" do
    it "is false for a buffer created without a block" do
      @buffer = IO::Buffer.for("test")
      @buffer.shared?.should be_false
    end

    it "is false for a buffer created with a block" do
      IO::Buffer.for(+"test") do |buffer|
        buffer.shared?.should be_false
      end
    end
  end

  ruby_version_is "3.3" do
    context "with a String-backed buffer created with .string" do
      it "is false" do
        IO::Buffer.string(4) do |buffer|
          buffer.shared?.should be_false
        end
      end
    end
  end

  # Always false for slices
  context "with a slice of a buffer" do
    context "created with .new" do
      it "is false when slicing an internal buffer" do
        @buffer = IO::Buffer.new(4)
        @buffer.slice.shared?.should be_false
      end

      it "is false when slicing a mapped buffer" do
        @buffer = IO::Buffer.new(4, IO::Buffer::MAPPED)
        @buffer.slice.shared?.should be_false
      end
    end

    context "created with .map" do
      it "is false when slicing a regular file-backed buffer" do
        File.open(__FILE__, "r") do |file|
          @buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY)
          @buffer.slice.shared?.should be_false
        end
      end

      ruby_version_is "3.3" do
        it "is false when slicing a private file-backed buffer" do
          File.open(__FILE__, "r") do |file|
            @buffer = IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY | IO::Buffer::PRIVATE)
            @buffer.slice.shared?.should be_false
          end
        end
      end
    end

    context "created with .for" do
      it "is false when slicing a buffer created without a block" do
        @buffer = IO::Buffer.for("test")
        @buffer.slice.shared?.should be_false
      end

      it "is false when slicing a buffer created with a block" do
        IO::Buffer.for(+"test") do |buffer|
          buffer.slice.shared?.should be_false
        end
      end
    end

    ruby_version_is "3.3" do
      context "created with .string" do
        it "is false" do
          IO::Buffer.string(4) do |buffer|
            buffer.slice.shared?.should be_false
          end
        end
      end
    end
  end
end
