# frozen_string_literal: true
require 'test/unit'
require 'cgi'

class CGIUtilTest < Test::Unit::TestCase

  def test_cgi_pretty
    assert_equal("<HTML>\n  <BODY>\n  </BODY>\n</HTML>\n",CGI.pretty("<HTML><BODY></BODY></HTML>"))
    assert_equal("<HTML>\n\t<BODY>\n\t</BODY>\n</HTML>\n",CGI.pretty("<HTML><BODY></BODY></HTML>","\t"))
  end

end
