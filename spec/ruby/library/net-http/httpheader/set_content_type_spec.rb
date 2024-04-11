require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'
require_relative 'shared/set_content_type'

describe "Net::HTTPHeader#set_content_type" do
  it_behaves_like :net_httpheader_set_content_type, :set_content_type
end
