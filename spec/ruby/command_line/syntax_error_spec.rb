require_relative '../spec_helper'

describe "The interpreter" do
  it "prints an error when given a file with invalid syntax" do
    out = ruby_exe(fixture(__FILE__, "bad_syntax.rb"), args: "2>&1", exit_status: 1)

    # it's tempting not to rely on error message and rely only on exception class name,
    # but CRuby before 3.2 doesn't print class name for syntax error
    out.should include_any_of("syntax error", "SyntaxError")
  end

  it "prints an error when given code via -e with invalid syntax" do
    out = ruby_exe(nil, args: "-e 'a{' 2>&1", exit_status: 1)

    # it's tempting not to rely on error message and rely only on exception class name,
    # but CRuby before 3.2 doesn't print class name for syntax error
    out.should include_any_of("syntax error", "SyntaxError")
  end
end
