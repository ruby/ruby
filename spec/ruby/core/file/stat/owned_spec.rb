require_relative '../../../spec_helper'
require_relative '../../../shared/file/owned'
require_relative 'fixtures/classes'

describe "File::Stat#owned?" do
  it_behaves_like :file_owned, :owned?, FileStat
end

describe "File::Stat#owned?" do
  before :each do
    @file = tmp("i_exist")
    touch(@file)
  end

  after :each do
    rm_r @file
  end

  it "returns true if the file is owned by the user" do
    st = File.stat(@file)
    st.should.owned?
  end

  platform_is_not :windows, :android do
    as_user do
      it "returns false if the file is not owned by the user" do
        system_file = '/etc/passwd'
        st = File.stat(system_file)
        st.should_not.owned?
      end
    end
  end
end
