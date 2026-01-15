require_relative '../../../spec_helper'
require 'net/http'
require_relative 'shared/version_1_1'

describe "Net::HTTP.version_1_1?" do
  it_behaves_like :net_http_version_1_1_p, :version_1_1?
end
