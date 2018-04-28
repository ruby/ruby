require_relative '../../../spec_helper'

describe "File::Stat#ino" do
  before :each do
    @file = tmp('i_exist')
    touch(@file) { |f| f.write "rubinius" }
  end

  after :each do
    rm_r @file
  end

  platform_is_not :windows do
    it "returns the ino of a File::Stat object" do
      st = File.stat(@file)
      st.ino.should be_kind_of(Integer)
      st.ino.should > 0
    end
  end

  platform_is :windows do
    it "returns BY_HANDLE_FILE_INFORMATION.nFileIndexHigh/Low of a File::Stat object" do
      st = File.stat(@file)
      st.ino.should be_kind_of(Integer)
      st.ino.should > 0
    end
  end
end
