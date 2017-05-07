require File.expand_path('../../../spec_helper', __FILE__)

describe "ARGF.binmode" do
  before :each do
    @file1    = fixture __FILE__, "file1.txt"
    @file2    = fixture __FILE__, "file2.txt"
    @bin_file = fixture __FILE__, "bin_file.txt"
  end

  it "returns self" do
    ruby_exe("puts(ARGF.binmode == ARGF)", args: @bin_file).chomp.should == 'true'
  end

  platform_is :windows do
    it "puts reading into binmode" do
      argf [@bin_file, @bin_file] do
        @argf.gets.should == "test\n"
        @argf.binmode
        @argf.gets.should == "test\r\n"
      end
    end

    it "puts alls subsequent stream reading through ARGF into binmode" do
      argf [@bin_file, @bin_file] do
        @argf.binmode
        @argf.gets.should == "test\r\n"
        @argf.gets.should == "test\r\n"
      end
    end
  end

  platform_is_not :windows do
    # This does nothing on Unix but it should not raise any errors.
    it "does not raise an error" do
      ruby_exe("ARGF.binmode", args: @bin_file)
      $?.should  be_kind_of(Process::Status)
      $?.to_i.should == 0
    end
  end

  it "sets the file's encoding to ASCII-8BIT" do
    script = fixture __FILE__, "encoding.rb"
    output = "true\n#{Encoding::ASCII_8BIT}\n#{Encoding::ASCII_8BIT}\n"
    ruby_exe(script, args: [@bin_file, @file1]).should == output
  end
end
