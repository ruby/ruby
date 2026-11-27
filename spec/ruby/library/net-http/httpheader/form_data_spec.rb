require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'

describe "Net::HTTPHeader#form_data=" do
  it "is an alias of Net::HTTPHeader#set_form_data" do
    Net::HTTPHeader.instance_method(:form_data=).should ==
      Net::HTTPHeader.instance_method(:set_form_data)
  end
end
