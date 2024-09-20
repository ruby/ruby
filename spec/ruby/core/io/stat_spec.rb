require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "IO#stat" do
  before :each do
    cmd = platform_is(:windows) ? 'rem' : 'cat'
    @io = IO.popen cmd, "r+"
  end

  after :each do
    @io.close unless @io.closed?
  end

  it "raises IOError on closed stream" do
    -> { IOSpecs.closed_io.stat }.should raise_error(IOError)
  end

  it "returns a File::Stat object for the stream" do
    STDOUT.stat.should be_an_instance_of(File::Stat)
  end

  it "can stat pipes" do
    @io.stat.should be_an_instance_of(File::Stat)
  end
end
