describe :file_readable_real, shared: true do
  before :each do
    @file = tmp('i_exist')
  end

  after :each do
    rm_r @file
  end

  it "returns true if named file is readable by the real user id of the process, otherwise false" do
    File.open(@file,'w') { @object.send(@method, @file).should == true }
  end

  it "accepts an object that has a #to_path method" do
    File.open(@file,'w') { @object.send(@method, mock_to_path(@file)).should == true }
  end

  platform_is_not :windows do
    as_real_superuser do
      context "when run by a real superuser" do
        it "returns true unconditionally" do
          file = tmp('temp.txt')
          touch file

          File.chmod(0333, file)
          @object.send(@method, file).should == true

          rm_r file
        end
      end
    end
  end
end

describe :file_readable_real_missing, shared: true do
  it "returns false if the file does not exist" do
    @object.send(@method, 'fake_file').should == false
  end
end
