require_relative '../spec_helper'

describe "The -l command line option" do
  before :each do
    @names  = fixture __FILE__, "full_names.txt"
  end

  it "chomps lines with default separator" do
    ruby_exe('puts $_.end_with?("\n")', options: "-n -l", escape: true,
             args: " < #{@names}").should ==
        "false\nfalse\nfalse\n"
  end

  it "chomps last line based on $/" do
    ruby_exe('BEGIN { $/ = "ones\n" }; puts $_', options: "-W0 -n -l", escape: true,
             args: " < #{@names}").should ==
        "alice j\nbob field\njames grey\n"
  end

  it "sets $\\ to the value of $/" do
    ruby_exe("puts $\\ == $/", options: "-W0 -n -l", escape: true,
             args: " < #{@names}").should ==
        "true\ntrue\ntrue\n"
  end

  it "sets $-l" do
    ruby_exe("puts $-l", options: "-n -l", escape: true,
                         args: " < #{@names}").should ==
      "true\ntrue\ntrue\n"
  end
end
