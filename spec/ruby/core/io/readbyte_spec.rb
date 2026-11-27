require_relative '../../spec_helper'

describe "IO#readbyte" do
  before :each do
    @io = File.open(__FILE__, 'r')
  end

  after :each do
    @io.close
  end

  it "reads one byte from the stream" do
    byte = @io.readbyte
    byte.should == ?r.getbyte(0)
    @io.pos.should == 1
  end

  it "raises EOFError on EOF" do
    @io.seek(999999)
    -> do
      @io.readbyte
    end.should.raise EOFError
  end

  it "reads after ungetc without character conversion" do
    @io.set_encoding("utf-8")
    c = @io.getc
    @io.ungetc(c)
    @io.readbyte.should == ?r.getbyte(0)
  end
end
