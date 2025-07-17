require_relative '../../spec_helper'
require "stringio"
require_relative 'fixtures/classes'
require_relative "shared/gets"

describe "StringIO#readline" do
  describe "when passed [separator]" do
    it_behaves_like :stringio_gets_separator, :readline

    it "raises an IOError if self is at the end" do
      @io = StringIO.new("this>is>an>example")

      @io.pos = 36
      -> { @io.readline(">") }.should raise_error(IOError)
    end
  end

  describe "when passed [limit]" do
    it_behaves_like :stringio_gets_limit, :readline

    it "raises an IOError if self is at the end" do
      @io = StringIO.new("this>is>an>example")

      @io.pos = 36
      -> { @io.readline(3) }.should raise_error(IOError)
    end
  end

  describe "when passed [separator] and [limit]" do
    it_behaves_like :stringio_gets_separator_and_limit, :readline

    it "raises an IOError if self is at the end" do
      @io = StringIO.new("this>is>an>example")

      @io.pos = 36
      -> { @io.readline(">", 3) }.should raise_error(IOError)
    end
  end

  describe "when passed no argument" do
    it_behaves_like :stringio_gets_no_argument, :readline

    it "raises an IOError if self is at the end" do
      @io = StringIO.new("this>is>an>example")

      @io.pos = 36
      -> { @io.readline }.should raise_error(IOError)
    end
  end

  describe "when passed [chomp]" do
    it_behaves_like :stringio_gets_chomp, :readline
  end

  describe "when in write-only mode" do
    it_behaves_like :stringio_gets_write_only, :readline
  end
end
