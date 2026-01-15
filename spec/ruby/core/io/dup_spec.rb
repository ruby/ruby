require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "IO#dup" do
  before :each do
    @file = tmp("spec_io_dup")
    @f = File.open @file, 'w+'
    @i = @f.dup

    @f.sync = true
    @i.sync = true
  end

  after :each do
    @i.close if @i && !@i.closed?
    @f.close if @f && !@f.closed?
    rm_r @file
  end

  it "returns a new IO instance" do
    @i.class.should == @f.class
  end

  it "sets a new descriptor on the returned object" do
    @i.fileno.should_not == @f.fileno
  end

  quarantine! do # This does not appear to be consistent across platforms
    it "shares the original stream between the two IOs" do
      start = @f.pos
      @i.pos.should == start

      s =  "Hello, wo.. wait, where am I?\n"
      s2 = "<evil voice>       Muhahahaa!"

      @f.write s
      @i.pos.should == @f.pos

      @i.rewind
      @i.gets.should == s

      @i.rewind
      @i.write s2

      @f.rewind
      @f.gets.should == "#{s2}\n"
    end
  end

  it "allows closing the new IO without affecting the original" do
    @i.close
    -> { @f.gets }.should_not raise_error(Exception)

    @i.should.closed?
    @f.should_not.closed?
  end

  it "allows closing the original IO without affecting the new one" do
    @f.close
    -> { @i.gets }.should_not raise_error(Exception)

    @i.should_not.closed?
    @f.should.closed?
  end

  it "raises IOError on closed stream" do
    -> { IOSpecs.closed_io.dup }.should raise_error(IOError)
  end

  it "always sets the close-on-exec flag for the new IO object" do
    @f.close_on_exec = true
    dup = @f.dup
    begin
      dup.should.close_on_exec?
    ensure
      dup.close
    end

    @f.close_on_exec = false
    dup = @f.dup
    begin
      dup.should.close_on_exec?
    ensure
      dup.close
    end
  end

  it "always sets the autoclose flag for the new IO object" do
    @f.autoclose = true
    dup = @f.dup
    begin
      dup.should.autoclose?
    ensure
      dup.close
    end

    @f.autoclose = false
    dup = @f.dup
    begin
      dup.should.autoclose?
    ensure
      dup.close
      @f.autoclose = true
    end
  end
end
