# frozen_string_literal: false
require 'test/unit'
module REXMLTestUtils
  def fixture_path(*components)
    File.join(File.dirname(__FILE__), "data", *components)
  end
end
