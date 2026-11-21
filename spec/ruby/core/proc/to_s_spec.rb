require_relative '../../spec_helper'

describe "Proc#to_s" do
  describe "for a proc created with Proc.new" do
    it "returns a description including file and line number" do
      Proc.new { "hello" }.to_s.should =~ /^#<Proc:([^ ]*?) #{Regexp.escape __FILE__}:#{__LINE__ }>$/
    end

    it "has a binary encoding" do
      Proc.new { "hello" }.to_s.encoding.should == Encoding::BINARY
    end
  end

  describe "for a proc created with lambda" do
    it "returns a description including '(lambda)' and including file and line number" do
      -> { "hello" }.to_s.should =~ /^#<Proc:([^ ]*?) #{Regexp.escape __FILE__}:#{__LINE__ } \(lambda\)>$/
    end

    it "has a binary encoding" do
      -> { "hello" }.to_s.encoding.should == Encoding::BINARY
    end
  end

  describe "for a proc created with proc" do
    it "returns a description including file and line number" do
      proc { "hello" }.to_s.should =~ /^#<Proc:([^ ]*?) #{Regexp.escape __FILE__}:#{__LINE__ }>$/
    end

    it "has a binary encoding" do
      proc { "hello" }.to_s.encoding.should == Encoding::BINARY
    end
  end

  describe "for a proc created with UnboundMethod#to_proc" do
    it "returns a description including '(lambda)' and optionally including file and line number" do
      def hello; end
      s = method("hello").to_proc.to_s
      if s.include? __FILE__
        s.should =~ /^#<Proc:([^ ]*?) #{Regexp.escape __FILE__}:#{__LINE__ - 3} \(lambda\)>$/
      else
        s.should =~ /^#<Proc:([^ ]*?) \(lambda\)>$/
      end
    end

    it "has a binary encoding" do
      def hello; end
      method("hello").to_proc.to_s.encoding.should == Encoding::BINARY
    end
  end

  describe "for a proc created with Symbol#to_proc" do
    it "returns a description including '(&:symbol)'" do
      proc = :foobar.to_proc
      proc.to_s.should.include?('(&:foobar)')
    end

    it "has a binary encoding" do
      proc = :foobar.to_proc
      proc.to_s.encoding.should == Encoding::BINARY
    end
  end
end
