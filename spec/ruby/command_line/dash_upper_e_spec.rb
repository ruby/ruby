require_relative '../spec_helper'

describe "ruby -E" do
  it "sets the external encoding with '-E external'" do
    result = ruby_exe("print Encoding.default_external", options: '-E euc-jp')
    result.should == "EUC-JP"
  end

  platform_is_not :windows do
    it "also sets the filesystem encoding with '-E external'" do
      result = ruby_exe("print Encoding.find('filesystem')", options: '-E euc-jp')
      result.should == "EUC-JP"
    end
  end

  it "sets the external encoding with '-E external:'" do
    result = ruby_exe("print Encoding.default_external", options: '-E Shift_JIS:')
    result.should == "Shift_JIS"
  end

  it "sets the internal encoding with '-E :internal'" do
    ruby_exe("print Encoding.default_internal", options: '-E :SHIFT_JIS').
      should == 'Shift_JIS'
  end

  it "sets the external and internal encodings with '-E external:internal'" do
    ruby_exe("puts Encoding.default_external, Encoding.default_internal", options: '-E euc-jp:SHIFT_JIS').
      should == "EUC-JP\nShift_JIS\n"
  end

  it "raises a RuntimeError if used with -U" do
    ruby_exe("p 1",
             options: '-Eascii:ascii -U',
             args: '2>&1',
             exit_status: 1).should =~ /RuntimeError/
  end
end
