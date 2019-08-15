require 'erb'
require_relative '../../../spec_helper'
require_relative 'shared/url_encode'

describe "ERB::Util.url_encode" do
  it_behaves_like :erb_util_url_encode, :url_encode
end
