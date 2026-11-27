require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#test" do
  before :all do
    @file = __dir__ + '/fixtures/classes.rb'
    @dir = __dir__ + '/fixtures'
  end

  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:test)
  end

  it "returns true when passed ?f if the argument is a regular file" do
    test(?f, @file).should == true
  end

  it "returns true when passed ?e if the argument is a file" do
    test(?e, @file).should == true
  end

  it "returns true when passed ?d if the argument is a directory" do
    test(?d, @dir).should == true
  end

  platform_is_not :windows do
    it "returns true when passed ?l if the argument is a symlink" do
      link = tmp("file_symlink.lnk")
      File.symlink(@file, link)
      begin
        test(?l, link).should == true
      ensure
        rm_r link
      end
    end
  end

  it "returns true when passed ?r if the argument is readable by the effective uid" do
    test(?r, @file).should == true
  end

  it "returns true when passed ?R if the argument is readable by the real uid" do
    test(?R, @file).should == true
  end

  context "writable test" do
    before do
      @tmp_file = tmp("file.kernel.test")
      touch(@tmp_file)
    end

    after do
      rm_r @tmp_file
    end

    it "returns true when passed ?w if the argument is readable by the effective uid" do
      test(?w, @tmp_file).should == true
    end

    it "returns true when passed ?W if the argument is readable by the real uid" do
      test(?W, @tmp_file).should == true
    end
  end

  context "time commands" do
    before :each do
      @tmp_file = File.new(tmp("file.kernel.test"), "w")
    end

    after :each do
      @tmp_file.close
      rm_r @tmp_file
    end

    it "returns the last access time for the provided file when passed ?A" do
      test(?A, @tmp_file).should == @tmp_file.atime
    end

    it "returns the time at which the file was created when passed ?C" do
      test(?C, @tmp_file).should == @tmp_file.ctime
    end

    it "returns the time at which the file was modified when passed ?M" do
      test(?M, @tmp_file).should == @tmp_file.mtime
    end
  end

  it "calls #to_path on second argument when passed ?f and a filename" do
    p = mock('path')
    p.should_receive(:to_path).and_return @file
    test(?f, p)
  end

  it "calls #to_path on second argument when passed ?e and a filename" do
    p = mock('path')
    p.should_receive(:to_path).and_return @file
    test(?e, p)
  end

  it "calls #to_path on second argument when passed ?d and a directory" do
    p = mock('path')
    p.should_receive(:to_path).and_return @dir
    test(?d, p)
  end
end

describe "Kernel.test" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:test)
  end
end
