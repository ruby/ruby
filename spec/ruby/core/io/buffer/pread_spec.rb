require_relative '../../../spec_helper'

describe "IO::Buffer#pread" do
  ruby_version_is "4.1" do
    it "raises FrozenError without modifying a frozen buffer" do
      file_name = tmp("io_buffer_pread")
      File.write(file_name, "data")

      begin
        buffer = IO::Buffer.new(4)
        buffer.set_string("test")
        buffer.freeze

        File.open(file_name, "rb") do |file|
          -> { buffer.pread(file, 0, 4) }.should.raise(FrozenError)
        end

        buffer.get_string.should == "test"
      ensure
        rm_r file_name
      end
    end
  end
end
