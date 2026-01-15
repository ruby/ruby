require_relative '../../spec_helper'

describe "IO#close_on_exec=" do
  before :each do
    @name = tmp('io_close_on_exec.txt')
    @io = new_io @name
  end

  after :each do
    @io.close unless @io.closed?
    rm_r @name
  end

  guard -> { platform_is_not :windows } do
    it "sets the close-on-exec flag if true" do
      @io.close_on_exec = true
      @io.should.close_on_exec?
    end

    it "sets the close-on-exec flag if non-false" do
      @io.close_on_exec = :true
      @io.should.close_on_exec?
    end

    it "unsets the close-on-exec flag if false" do
      @io.close_on_exec = true
      @io.close_on_exec = false
      @io.should_not.close_on_exec?
    end

    it "unsets the close-on-exec flag if nil" do
      @io.close_on_exec = true
      @io.close_on_exec = nil
      @io.should_not.close_on_exec?
    end

    it "ensures the IO's file descriptor is closed in exec'ed processes" do
      require 'fcntl'
      @io.close_on_exec = true
      (@io.fcntl(Fcntl::F_GETFD) & Fcntl::FD_CLOEXEC).should == Fcntl::FD_CLOEXEC
    end

    it "raises IOError if called on a closed IO" do
      @io.close
      -> { @io.close_on_exec = true }.should raise_error(IOError)
    end
  end
end

describe "IO#close_on_exec?" do
  before :each do
    @name = tmp('io_is_close_on_exec.txt')
    @io = new_io @name
  end

  after :each do
    @io.close unless @io.closed?
    rm_r @name
  end

  guard -> { platform_is_not :windows } do
    it "returns true by default" do
      @io.should.close_on_exec?
    end

    it "returns true if set" do
      @io.close_on_exec = true
      @io.should.close_on_exec?
    end

    it "raises IOError if called on a closed IO" do
      @io.close
      -> { @io.close_on_exec? }.should raise_error(IOError)
    end
  end
end
