require_relative '../spec_helper'

describe 'The --encoding command line option' do
  before :each do
    @test_string = "print [Encoding.default_external.name, Encoding.default_internal&.name].inspect"
  end

  describe 'sets Encoding.default_external and optionally Encoding.default_internal' do
    it "if given a single encoding with an =" do
      ruby_exe(@test_string, options: '--disable-gems --encoding=big5').should == [Encoding::Big5.name, nil].inspect
    end

    it "if given a single encoding as a separate argument" do
      ruby_exe(@test_string, options: '--disable-gems --encoding big5').should == [Encoding::Big5.name, nil].inspect
    end

    it "if given two encodings with an =" do
      ruby_exe(@test_string, options: '--disable-gems --encoding=big5:utf-32be').should == [Encoding::Big5.name, Encoding::UTF_32BE.name].inspect
    end

    it "if given two encodings as a separate argument" do
      ruby_exe(@test_string, options: '--disable-gems --encoding big5:utf-32be').should == [Encoding::Big5.name, Encoding::UTF_32BE.name].inspect
    end

    it "if given two encodings as a separate argument" do
      ruby_exe(@test_string, options: '--disable-gems --encoding big5:utf-32be').should == [Encoding::Big5.name, Encoding::UTF_32BE.name].inspect
    end
  end

  it "does not accept a third encoding" do
    ruby_exe(@test_string, options: '--disable-gems --encoding big5:utf-32be:utf-32le', args: '2>&1').should =~ /extra argument for --encoding: utf-32le/
  end
end
