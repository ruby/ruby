describe :file_executable_real, shared: true do
  before :each do
    @file1 = tmp('temp1.txt.exe')
    @file2 = tmp('temp2.txt')

    touch @file1
    touch @file2

    File.chmod(0755, @file1)
  end

  after :each do
    rm_r @file1, @file2
  end

  platform_is_not :windows do
    it "returns true if the file its an executable" do
      @object.send(@method, @file1).should == true
      @object.send(@method, @file2).should == false
    end

    it "accepts an object that has a #to_path method" do
      @object.send(@method, mock_to_path(@file1)).should == true
    end
  end

  it "returns true if named file is readable by the real user id of the process, otherwise false" do
    @object.send(@method, @file1).should == true
  end

  it "raises an ArgumentError if not passed one argument" do
    -> { @object.send(@method) }.should raise_error(ArgumentError)
  end

  it "raises a TypeError if not passed a String type" do
    -> { @object.send(@method, 1)     }.should raise_error(TypeError)
    -> { @object.send(@method, nil)   }.should raise_error(TypeError)
    -> { @object.send(@method, false) }.should raise_error(TypeError)
  end
end

describe :file_executable_real_missing, shared: true do
  it "returns false if the file does not exist" do
    @object.send(@method, 'fake_file').should == false
  end
end
