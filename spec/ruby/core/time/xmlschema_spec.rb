require_relative '../../spec_helper'
require_relative 'shared/xmlschema'

describe "Time#xmlschema" do
  it_behaves_like :time_xmlschema, :xmlschema
end
