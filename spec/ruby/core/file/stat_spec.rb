require_relative '../../spec_helper'
require_relative 'shared/stat'

describe "File.stat" do
  it_behaves_like :file_stat, :stat
end

platform_is_not :windows do
  describe "File.stat" do
    before :each do
      @file = tmp('i_exist')
      @link = tmp('i_am_a_symlink')
      touch(@file) { |f| f.write "rubinius" }
    end

    after :each do
      rm_r @link, @file
    end

    it "returns information for a file that has been deleted but is still open" do
      File.open(@file) do |f|
        rm_r @file

        st = f.stat

        st.should.file?
        st.should_not.zero?
        st.size.should == 8
        st.size?.should == 8
        st.blksize.should >= 0
        st.atime.should be_kind_of(Time)
        st.ctime.should be_kind_of(Time)
        st.mtime.should be_kind_of(Time)
      end
    end

    it "returns a File::Stat object with file properties for a symlink" do
      File.symlink(@file, @link)
      st = File.stat(@link)

      st.should.file?
      st.should_not.symlink?
    end

    it "returns an error when given missing non-ASCII path" do
      missing_path = "/missingfilepath\xE3E4".b
      -> {
        File.stat(missing_path)
      }.should raise_error(SystemCallError) { |e|
        [Errno::ENOENT, Errno::EILSEQ].should include(e.class)
        e.message.should include(missing_path)
      }
    end
  end
end
