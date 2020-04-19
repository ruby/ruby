require_relative "test_helper"
require "abbrev"

class AbbrevTest < StdlibTest
  target Abbrev
  library "abbrev"

  using hook.refinement

  def test_abbrev
    Abbrev.abbrev([])
    Abbrev.abbrev(%w(abbrev))
    Abbrev.abbrev(%w(abbrev), 'abb')
    Abbrev.abbrev(%w(abbrev), /^abb/)
    Abbrev.abbrev(%w(abbrev), nil)
  end
end
