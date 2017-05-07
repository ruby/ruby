require File.expand_path('../../../spec_helper', __FILE__)

# These specs need to be run to a separate process as there is no way to reset ARGF encoding
describe "ARGF.set_encoding" do
  before :each do
    @file = fixture __FILE__, "file1.txt"
  end

  it "sets the external encoding when passed an encoding instance" do
    enc = ruby_exe('ARGF.set_encoding(Encoding::UTF_8); print ARGF.gets.encoding', args: [@file])
    enc.should == "UTF-8"
  end

  it "sets the external encoding when passed an encoding name" do
    enc = ruby_exe('ARGF.set_encoding("utf-8"); print ARGF.gets.encoding', args: [@file])
    enc.should == "UTF-8"
  end

  it "sets the external, internal encoding when passed two encoding instances" do
    enc = ruby_exe('ARGF.set_encoding(Encoding::UTF_8, Encoding::EUC_JP); print ARGF.gets.encoding', args: [@file])
    enc.should == "EUC-JP"
  end

  it "sets the external, internal encoding when passed 'ext:int' String" do
    enc = ruby_exe('ARGF.set_encoding("utf-8:euc-jp"); print ARGF.gets.encoding', args: [@file])
    enc.should == "EUC-JP"
  end
end
