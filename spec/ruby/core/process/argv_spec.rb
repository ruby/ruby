require_relative '../../spec_helper'

describe "Process.argv" do
  it "returns the original process command line arguments including Ruby's own flags" do
    code = "print Process.argv[1..-1].inspect"
    ruby_exe(code, options: "--disable-gems --encoding big5", escape: false).should == [
      "--disable-gems",
      "--encoding",
      "big5",
      "-e",
      code,
    ].inspect
  end
end
