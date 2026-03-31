require_relative '../../spec_helper'
require "stringio"
require_relative "shared/gets"

describe "StringIO#gets" do
  describe "when passed [separator]" do
    it_behaves_like :stringio_gets_separator, :gets

    it "returns nil if self is at the end" do
      @io = StringIO.new("this>is>an>example")

      @io.pos = 36
      @io.gets(">").should be_nil
      @io.gets(">").should be_nil
    end
  end

  describe "when passed [limit]" do
    it_behaves_like :stringio_gets_limit, :gets

    it "returns nil if self is at the end" do
      @io = StringIO.new("this>is>an>example")

      @io.pos = 36
      @io.gets(3).should be_nil
      @io.gets(3).should be_nil
    end
  end

  describe "when passed [separator] and [limit]" do
    it_behaves_like :stringio_gets_separator_and_limit, :gets

    it "returns nil if self is at the end" do
      @io = StringIO.new("this>is>an>example")

      @io.pos = 36
      @io.gets(">", 3).should be_nil
      @io.gets(">", 3).should be_nil
    end
  end

  describe "when passed no argument" do
    it_behaves_like :stringio_gets_no_argument, :gets

    it "returns nil if self is at the end" do
      @io = StringIO.new("this>is>an>example")

      @io.pos = 36
      @io.gets.should be_nil
      @io.gets.should be_nil
    end
  end

  describe "when passed [chomp]" do
    it_behaves_like :stringio_gets_chomp, :gets
  end

  describe "when in write-only mode" do
    it_behaves_like :stringio_gets_write_only, :gets
  end
end
