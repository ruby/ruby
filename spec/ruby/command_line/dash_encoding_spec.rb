require_relative '../spec_helper'

describe 'The --encoding command line option' do
  before :each do
    @test_string = "print [Encoding.default_external.name, Encoding.default_internal&.name].inspect"
    @enc2 = /mswin|mingw/ !~ RUBY_PLATFORM ? 'UTF-32BE' : 'Windows-1256'
  end

  describe 'sets Encoding.default_external and optionally Encoding.default_internal' do
    it "if given a single encoding with an =" do
      ruby_exe(@test_string, options: "--disable-gems --encoding=big5").should == [Encoding::Big5.name, nil].inspect
    end

    it "if given a single encoding as a separate argument" do
      ruby_exe(@test_string, options: "--disable-gems --encoding big5").should == [Encoding::Big5.name, nil].inspect
    end

    it "if given two encodings with an =" do
      ruby_exe(@test_string, options: "--disable-gems --encoding=big5:#{@enc2}").should == [Encoding::Big5.name, @enc2].inspect
    end

    it "if given two encodings as a separate argument" do
      ruby_exe(@test_string, options: "--disable-gems --encoding big5:#{@enc2}").should == [Encoding::Big5.name, @enc2].inspect
    end

    it "if given two encodings as a separate argument" do
      ruby_exe(@test_string, options: "--disable-gems --encoding big5:#{@enc2}").should == [Encoding::Big5.name, @enc2].inspect
    end
  end

  it "does not accept a third encoding" do
    ruby_exe(@test_string, options: "--disable-gems --encoding big5:#{@enc2}:#{@enc2}", args: '2>&1').should =~ /extra argument for --encoding: #{@enc2}/
  end
end
