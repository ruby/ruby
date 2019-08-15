require 'erb'
require_relative '../../spec_helper'

describe "ERB#filename" do
  it "raises an exception if there are errors processing content" do
    filename = 'foobar.rhtml'
    erb = ERB.new('<% if true %>')   # will raise SyntaxError
    erb.filename = filename
    -> {
      begin
        erb.result(binding)
      rescue Exception => e
        @ex = e
        raise e
      end
    }.should raise_error(SyntaxError)
    expected = filename

    @ex.message =~ /^(.*?):(\d+): /
    $1.should == expected
    $2.to_i.should == 1
  end

  it "uses '(erb)' as filename when filename is not set" do
    erb = ERB.new('<% if true %>')   # will raise SyntaxError
    -> {
      begin
        erb.result(binding)
      rescue Exception => e
        @ex = e
        raise e
      end
    }.should raise_error(SyntaxError)
    expected = '(erb)'

    @ex.message =~ /^(.*?):(\d+): /
    $1.should == expected
    $2.to_i.should == 1
  end
end
