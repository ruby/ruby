require_relative '../../../spec_helper'
require 'cgi'
require_relative 'fixtures/common'
require_relative 'shared/popup_menu'

describe "CGI::HtmlExtension#popup_menu" do
  it_behaves_like :cgi_htmlextension_popup_menu, :popup_menu
end
