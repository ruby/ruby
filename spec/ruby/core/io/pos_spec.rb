require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/pos'

describe "IO#pos" do
  before :each do
    @fname = tmp('test.txt')
    File.open(@fname, 'w') { |f| f.write "123" }
  end

  after :each do
    rm_r @fname
  end

  it "gets the offset" do
    File.open @fname do |f|
      f.pos.should == 0
      f.read 1
      f.pos.should == 1
      f.read 2
      f.pos.should == 3
    end
  end

  it "raises IOError on closed stream" do
    -> { IOSpecs.closed_io.pos }.should.raise(IOError)
  end

  it "resets #eof?" do
    open @fname do |io|
      io.read 1
      io.read 1
      io.pos
      io.should_not.eof?
    end
  end
end

describe "IO#pos=" do
  it_behaves_like :io_set_pos, :pos=
end
