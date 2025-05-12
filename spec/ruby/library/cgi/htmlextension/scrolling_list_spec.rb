require_relative '../../../spec_helper'

ruby_version_is ""..."3.5" do
  require_relative 'fixtures/common'
  require 'cgi'
  require_relative 'shared/popup_menu'

  describe "CGI::HtmlExtension#scrolling_list" do
    it_behaves_like :cgi_htmlextension_popup_menu, :scrolling_list
  end
end
