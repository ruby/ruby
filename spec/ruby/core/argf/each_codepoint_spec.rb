require_relative '../../spec_helper'

describe "ARGF.each_codepoint" do
  before :each do
    file1_name = fixture __FILE__, "file1.txt"
    file2_name = fixture __FILE__, "file2.txt"
    @filenames = [file1_name, file2_name]

    @codepoints = File.read(file1_name).codepoints
    @codepoints.concat File.read(file2_name).codepoints
  end

  it "is a public method" do
    argf @filenames do
      @argf.public_methods(false).should.include?(:each_codepoint)
    end
  end

  it "does not require arguments" do
    argf @filenames do
      @argf.method(:each_codepoint).arity.should == 0
    end
  end

  it "returns self when passed a block" do
    argf @filenames do
      @argf.each_codepoint {}.should.equal?(@argf)
    end
  end

  it "returns an Enumerator when passed no block" do
    argf @filenames do
      @argf.each_codepoint.should.instance_of?(Enumerator)
    end
  end

  it "yields each codepoint of all streams" do
    argf @filenames do
      @argf.each_codepoint.to_a.should == @codepoints
    end
  end

  describe "when no block is given" do
    it "returns an Enumerator" do
      argf @filenames do
        @argf.each_codepoint.should.instance_of?(Enumerator)
      end
    end

    describe "returned Enumerator" do
      describe "size" do
        it "should return nil" do
          argf @filenames do
            @argf.each_codepoint.size.should == nil
          end
        end
      end
    end
  end
end
