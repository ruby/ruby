require_relative '../../../spec_helper'
require 'net/http'
require_relative 'fixtures/classes'
require_relative 'shared/set_form_data'

describe "Net::HTTPHeader#form_data=" do
  it_behaves_like :net_httpheader_set_form_data, :form_data=
end
