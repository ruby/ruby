# -*- encoding: utf-8 -*-

require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "StringIO#puts when passed an Array" do
  before :each do
    @io = StringIO.new
  end

  it "writes each element of the passed Array to self, separated by a newline" do
    @io.puts([1, 2, 3, 4])
    @io.string.should == "1\n2\n3\n4\n"

    @io.puts([1, 2], [3, 4])
    @io.string.should == "1\n2\n3\n4\n1\n2\n3\n4\n"
  end

  it "flattens nested Arrays" do
    @io.puts([1, [2, [3, [4]]]])
    @io.string.should == "1\n2\n3\n4\n"
  end

  it "handles self-recursive arrays correctly" do
    (ary = [5])
    ary << ary
    @io.puts(ary)
    @io.string.should == "5\n[...]\n"
  end

  it "does not honor the global output record separator $\\" do
    begin
      old_rs = $\
      suppress_warning {$\ = "test"}
      @io.puts([1, 2, 3, 4])
      @io.string.should == "1\n2\n3\n4\n"
    ensure
      suppress_warning {$\ = old_rs}
    end
  end

  it "first tries to convert each Array element to an Array using #to_ary" do
    obj = mock("Object")
    obj.should_receive(:to_ary).and_return(["to_ary"])
    @io.puts([obj])
    @io.string.should == "to_ary\n"
  end

  it "then tries to convert each Array element to a String using #to_s" do
    obj = mock("Object")
    obj.should_receive(:to_s).and_return("to_s")
    @io.puts([obj])
    @io.string.should == "to_s\n"
  end

  it "returns general object info if :to_s does not return a string" do
    object = mock('hola')
    object.should_receive(:to_s).and_return(false)

    @io.puts(object).should == nil
    @io.string.should == object.inspect.split(" ")[0] + ">\n"
  end
end

describe "StringIO#puts when passed 1 or more objects" do
  before :each do
    @io = StringIO.new
  end

  it "does not honor the global output record separator $\\" do
    begin
      old_rs = $\
      suppress_warning {$\ = "test"}
      @io.puts(1, 2, 3, 4)
      @io.string.should == "1\n2\n3\n4\n"
    ensure
      suppress_warning {$\ = old_rs}
    end
  end

  it "does not put a \\n after each Objects that end in a newline" do
    @io.puts("1\n", "2\n", "3\n")
    @io.string.should == "1\n2\n3\n"
  end

  it "first tries to convert each Object to an Array using #to_ary" do
    obj = mock("Object")
    obj.should_receive(:to_ary).and_return(["to_ary"])
    @io.puts(obj)
    @io.string.should == "to_ary\n"
  end

  it "then tries to convert each Object to a String using #to_s" do
    obj = mock("Object")
    obj.should_receive(:to_s).and_return("to_s")
    @io.puts(obj)
    @io.string.should == "to_s\n"
  end

  it "prints a newline when passed an empty string" do
    @io.puts ''
    @io.string.should == "\n"
  end

  it "handles concurrent writes correctly" do
    n = 8
    go = false
    threads = n.times.map { |i|
      Thread.new {
        Thread.pass until go
        @io.puts i
      }
    }
    go = true
    threads.each(&:join)
    @io.string.size.should == n.times.map { |i| "#{i}\n" }.join.size
  end
end

describe "StringIO#puts when passed no arguments" do
  before :each do
    @io = StringIO.new
  end

  it "returns nil" do
    @io.puts.should be_nil
  end

  it "prints a newline" do
    @io.puts
    @io.string.should == "\n"
  end

  it "does not honor the global output record separator $\\" do
    begin
      old_rs = $\
      suppress_warning {$\ = "test"}
      @io.puts
      @io.string.should == "\n"
    ensure
      suppress_warning {$\ = old_rs}
    end
  end
end

describe "StringIO#puts when in append mode" do
  before :each do
    @io = StringIO.new("example", "a")
  end

  it "appends the passed argument to the end of self" do
    @io.puts(", just testing")
    @io.string.should == "example, just testing\n"

    @io.puts(" and more testing")
    @io.string.should == "example, just testing\n and more testing\n"
  end

  it "correctly updates self's position" do
    @io.puts(", testing")
    @io.pos.should eql(17)
  end
end

describe "StringIO#puts when self is not writable" do
  it "raises an IOError" do
    io = StringIO.new("test", "r")
    -> { io.puts }.should raise_error(IOError)

    io = StringIO.new("test")
    io.close_write
    -> { io.puts }.should raise_error(IOError)
  end
end

describe "StringIO#puts when passed an encoded string" do
  it "stores the bytes unmodified" do
    io = StringIO.new("")
    io.puts "\x00\x01\x02"
    io.puts "æåø"

    io.string.should == "\x00\x01\x02\næåø\n"
  end
end
