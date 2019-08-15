require_relative '../../dir/fixtures/common'

describe :open_directory, shared: true do
  it "opens directories" do
    file = File.send(@method, tmp(""))
    begin
      file.should be_kind_of(File)
    ensure
      file.close
    end
  end
end
