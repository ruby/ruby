# encoding: binary
require 'strscan'

describe :strscan_get_byte, shared: true do
  it "scans one byte and returns it" do
    s = StringScanner.new('abc5.')
    s.send(@method).should == 'a'
    s.send(@method).should == 'b'
    s.send(@method).should == 'c'
    s.send(@method).should == '5'
    s.send(@method).should == '.'
  end

  it "is not multi-byte character sensitive" do
    s = StringScanner.new("\244\242")
    s.send(@method).should == "\244"
    s.send(@method).should == "\242"
  end

  it "returns nil at the end of the string" do
    # empty string case
    s = StringScanner.new('')
    s.send(@method).should == nil
    s.send(@method).should == nil

    # non-empty string case
    s = StringScanner.new('a')
    s.send(@method) # skip one
    s.send(@method).should == nil
  end

  describe "#[] successive call with a capture group name" do
    # https://github.com/ruby/strscan/issues/139
    ruby_version_is ""..."3.5" do # Don't run on 3.5.0dev that already contains not released fixes
    version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
      it "returns nil" do
        s = StringScanner.new("This is a test")
        s.send(@method)
        s.should.matched?
        s[:a].should be_nil
      end
    end
    end
    version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4.3"
      it "raises IndexError" do
        s = StringScanner.new("This is a test")
        s.send(@method)
        s.should.matched?
        -> { s[:a] }.should raise_error(IndexError)
      end
    end

    it "returns a matching character when given Integer index" do
      s = StringScanner.new("This is a test")
      s.send(@method)
      s[0].should == "T"
    end

    # https://github.com/ruby/strscan/issues/135
    ruby_version_is ""..."3.5" do # Don't run on 3.5.0dev that already contains not released fixes
    version_is StringScanner::Version, "3.1.1"..."3.1.3" do # ruby_version_is "3.4.0"..."3.4.3"
      it "ignores the previous matching with Regexp" do
        s = StringScanner.new("This is a test")
        s.exist?(/(?<a>This)/)
        s.should.matched?
        s[:a].should == "This"

        s.send(@method)
        s.should.matched?
        s[:a].should be_nil
      end
    end
    end
    version_is StringScanner::Version, "3.1.3" do # ruby_version_is "3.4.3"
      it "ignores the previous matching with Regexp" do
        s = StringScanner.new("This is a test")
        s.exist?(/(?<a>This)/)
        s.should.matched?
        s[:a].should == "This"

        s.send(@method)
        s.should.matched?
        -> { s[:a] }.should raise_error(IndexError)
      end
    end
  end
end
