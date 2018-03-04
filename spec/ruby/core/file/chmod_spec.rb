require_relative '../../spec_helper'

describe "File#chmod" do
  before :each do
    @filename = tmp('i_exist.exe')
    @file = File.open(@filename, 'w')
  end

  after :each do
    @file.close
    rm_r @filename
  end

  it "returns 0 if successful" do
    @file.chmod(0755).should == 0
  end

  it "raises RangeError with too large values" do
    -> { @file.chmod(2**64) }.should raise_error(RangeError)
    -> { @file.chmod(-2**63 - 1) }.should raise_error(RangeError)
  end

  it "invokes to_int on non-integer argument" do
    mode = File.stat(@filename).mode
    (obj = mock('mode')).should_receive(:to_int).and_return(mode)
    @file.chmod(obj)
    File.stat(@filename).mode.should == mode
  end

  platform_is :windows do
    it "with '0444' makes file readable and executable but not writable" do
      @file.chmod(0444)
      File.readable?(@filename).should == true
      File.writable?(@filename).should == false
      File.executable?(@filename).should == true
    end

    it "with '0644' makes file readable and writable and also executable" do
      @file.chmod(0644)
      File.readable?(@filename).should == true
      File.writable?(@filename).should == true
      File.executable?(@filename).should == true
    end
  end

  platform_is_not :windows do
    as_user do
      it "with '0222' makes file writable but not readable or executable" do
        @file.chmod(0222)
        File.readable?(@filename).should == false
        File.writable?(@filename).should == true
        File.executable?(@filename).should == false
      end

      it "with '0444' makes file readable but not writable or executable" do
        @file.chmod(0444)
        File.readable?(@filename).should == true
        File.writable?(@filename).should == false
        File.executable?(@filename).should == false
      end

      it "with '0666' makes file readable and writable but not executable" do
        @file.chmod(0666)
        File.readable?(@filename).should == true
        File.writable?(@filename).should == true
        File.executable?(@filename).should == false
      end

      it "with '0111' makes file executable but not readable or writable" do
        @file.chmod(0111)
        File.readable?(@filename).should == false
        File.writable?(@filename).should == false
        File.executable?(@filename).should == true
      end

      it "modifies the permission bits of the files specified" do
        @file.chmod(0755)
        File.stat(@filename).mode.should == 33261
      end
    end
  end
end

describe "File.chmod" do
  before :each do
    @file = tmp('i_exist.exe')
    touch @file
    @count = File.chmod(0755, @file)
  end

  after :each do
    rm_r @file
  end

  it "returns the number of files modified" do
    @count.should == 1
  end

  it "raises RangeError with too large values" do
    -> { File.chmod(2**64, @file) }.should raise_error(RangeError)
    -> { File.chmod(-2**63 - 1, @file) }.should raise_error(RangeError)
  end

  it "accepts an object that has a #to_path method" do
    File.chmod(0, mock_to_path(@file))
  end

  it "throws a TypeError if the given path is not coercable into a string" do
    lambda { File.chmod(0, []) }.should raise_error(TypeError)
  end

  it "raises an error for a non existent path" do
    lambda {
      File.chmod(0644, "#{@file}.not.existing")
    }.should raise_error(Errno::ENOENT)
  end

  it "invokes to_int on non-integer argument" do
    mode = File.stat(@file).mode
    (obj = mock('mode')).should_receive(:to_int).and_return(mode)
    File.chmod(obj, @file)
    File.stat(@file).mode.should == mode
  end

  it "invokes to_str on non-string file names" do
    mode = File.stat(@file).mode
    (obj = mock('path')).should_receive(:to_str).and_return(@file)
    File.chmod(mode, obj)
    File.stat(@file).mode.should == mode
  end

  platform_is :windows do
    it "with '0444' makes file readable and executable but not writable" do
      File.chmod(0444, @file)
      File.readable?(@file).should == true
      File.writable?(@file).should == false
      File.executable?(@file).should == true
    end

    it "with '0644' makes file readable and writable and also executable" do
      File.chmod(0644, @file)
      File.readable?(@file).should == true
      File.writable?(@file).should == true
      File.executable?(@file).should == true
    end
  end

  platform_is_not :windows do
    as_user do
      it "with '0222' makes file writable but not readable or executable" do
        File.chmod(0222, @file)
        File.readable?(@file).should == false
        File.writable?(@file).should == true
        File.executable?(@file).should == false
      end

      it "with '0444' makes file readable but not writable or executable" do
        File.chmod(0444, @file)
        File.readable?(@file).should == true
        File.writable?(@file).should == false
        File.executable?(@file).should == false
      end
    end

    it "with '0666' makes file readable and writable but not executable" do
      File.chmod(0666, @file)
      File.readable?(@file).should == true
      File.writable?(@file).should == true
      File.executable?(@file).should == false
    end

    as_user do
      it "with '0111' makes file executable but not readable or writable" do
        File.chmod(0111, @file)
        File.readable?(@file).should == false
        File.writable?(@file).should == false
        File.executable?(@file).should == true
      end
    end

    it "modifies the permission bits of the files specified" do
      File.stat(@file).mode.should == 33261
    end
  end
end
