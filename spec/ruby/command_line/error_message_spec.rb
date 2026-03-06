require_relative '../spec_helper'

describe "The error message caused by an exception" do
  it "is not printed to stdout" do
    out = ruby_exe("this_does_not_exist", args: "2> #{File::NULL}", exit_status: 1)
    out.chomp.should.empty?

    out = ruby_exe("end #syntax error", args: "2> #{File::NULL}", exit_status: 1)
    out.chomp.should.empty?
  end

  it "is not modified with extra escaping of control characters and backslashes" do
    out = ruby_exe('raise "\e[31mRed\e[0m error\\\\message"', args: "2>&1", exit_status: 1)
    out.chomp.should include("\e[31mRed\e[0m error\\message")
  end
end
