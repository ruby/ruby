require 'erb'
require_relative '../../../spec_helper'
require_relative 'shared/html_escape'

describe "ERB::Util.h" do
  it_behaves_like :erb_util_html_escape, :h
end
