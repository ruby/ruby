# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is ''...'3.0' do
  describe "IO#bytes" do
    before :each do
      @io = IOSpecs.io_fixture "lines.txt"
      @verbose, $VERBOSE = $VERBOSE, nil
    end

    after :each do
      $VERBOSE = @verbose
      @io.close unless @io.closed?
    end

    it "returns an enumerator of the next bytes from the stream" do
      enum = @io.bytes
      enum.should be_an_instance_of(Enumerator)
      @io.readline.should == "Voici la ligne une.\n"
      enum.first(5).should == [81, 117, 105, 32, 195]
    end

    it "yields each byte" do
      count = 0
      ScratchPad.record []
      @io.each_byte do |byte|
        ScratchPad << byte
        break if 4 < count += 1
      end

      ScratchPad.recorded.should == [86, 111, 105, 99, 105]
    end

    it "raises an IOError on closed stream" do
      enum = IOSpecs.closed_io.bytes
      -> { enum.first }.should raise_error(IOError)
    end

    it "raises an IOError on an enumerator for a stream that has been closed" do
      enum = @io.bytes
      enum.first.should == 86
      @io.close
      -> { enum.first }.should raise_error(IOError)
    end
  end
end
