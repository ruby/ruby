require_relative '../../../spec_helper'
require_relative '../../../shared/file/pipe'
require_relative 'fixtures/classes'

describe "File::Stat#pipe?" do
  it_behaves_like :file_pipe, :pipe?, FileStat
end

describe "File::Stat#pipe?" do
  it "returns false if the file is not a pipe" do
    filename = tmp("i_exist")
    touch(filename)

    st = File.stat(filename)
    st.should_not.pipe?

    rm_r filename
  end

  platform_is_not :windows do
    it "returns true if the file is a pipe" do
      filename = tmp("i_am_a_pipe")
      File.mkfifo(filename)

      st = File.stat(filename)
      st.should.pipe?

      rm_r filename
    end
  end

end
