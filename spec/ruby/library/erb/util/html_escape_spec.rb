require 'erb'
require_relative '../../../spec_helper'
require_relative 'shared/html_escape'

describe "ERB::Util.html_escape" do
  it_behaves_like :erb_util_html_escape, :html_escape
end
