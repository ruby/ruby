require_relative '../../spec_helper'
require 'ripper'

describe "Ripper.sexp" do
  it "returns an s-expression for a method declaration" do
    expected = [:program,
                [[:def,
                  [:@ident, "hello", [1, 4]],
                  [:params, nil, nil, nil, nil, nil, nil, nil],
                  [:bodystmt, [[:@int, "42", [1, 11]]], nil, nil, nil]]]]
    Ripper.sexp("def hello; 42; end").should == expected
  end
end
