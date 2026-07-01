require_relative '../../spec_helper'

describe "ARGF.each_byte" do
  before :each do
    @file1_name = fixture __FILE__, "file1.txt"
    @file2_name = fixture __FILE__, "file2.txt"

    @bytes = []
    File.read(@file1_name).each_byte { |b| @bytes << b }
    File.read(@file2_name).each_byte { |b| @bytes << b }
  end

  it "yields each byte of all streams to the passed block" do
    argf [@file1_name, @file2_name] do
      bytes = []
      @argf.each_byte { |b| bytes << b }
      bytes.should == @bytes
    end
  end

  it "returns self when passed a block" do
    argf [@file1_name, @file2_name] do
      @argf.each_byte {}.should.equal?(@argf)
    end
  end

  it "returns an Enumerator when passed no block" do
    argf [@file1_name, @file2_name] do
      enum = @argf.each_byte
      enum.should.instance_of?(Enumerator)

      bytes = []
      enum.each { |b| bytes << b }
      bytes.should == @bytes
    end
  end

  describe "when no block is given" do
    it "returns an Enumerator" do
      argf [@file1_name, @file2_name] do
        enum = @argf.each_byte
        enum.should.instance_of?(Enumerator)

        bytes = []
        enum.each { |b| bytes << b }
        bytes.should == @bytes
      end
    end

    describe "returned Enumerator" do
      describe "size" do
        it "should return nil" do
          argf [@file1_name, @file2_name] do
            @argf.each_byte.size.should == nil
          end
        end
      end
    end
  end
end
