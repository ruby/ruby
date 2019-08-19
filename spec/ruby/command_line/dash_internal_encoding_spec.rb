require_relative '../spec_helper'

describe 'The --internal-encoding command line option sets Encoding.default_internal' do
  before :each do
    @test_string = "print Encoding.default_internal.name"
  end

  it "if given an encoding with an =" do
    ruby_exe(@test_string, options: '--internal-encoding=big5').should == Encoding::Big5.name
  end

  it "if given an encoding as a separate argument" do
    ruby_exe(@test_string, options: '--internal-encoding big5').should == Encoding::Big5.name
  end
end
