require_relative '../../spec_helper'
require_relative 'shared/xmlschema'

describe "Time#iso8601" do
  it_behaves_like :time_xmlschema, :iso8601
end
