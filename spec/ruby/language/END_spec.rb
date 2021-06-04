require_relative '../spec_helper'

describe "The END keyword" do
  it "runs only once for multiple calls" do
    ruby_exe("10.times { END { puts 'foo' }; } ").should == "foo\n"
  end

  it "runs last in a given code unit" do
    ruby_exe("END { puts 'bar' }; puts'foo'; ").should == "foo\nbar\n"
  end

  it "runs multiple ends in LIFO order" do
    ruby_exe("END { puts 'foo' }; END { puts 'bar' }").should == "bar\nfoo\n"
  end
end
