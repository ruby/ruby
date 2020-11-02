require "tempfile"
require "test/unit"
require "webrick/httpauth/htgroup"

class TestHtgroup < Test::Unit::TestCase
  def test_htgroup
    Tempfile.create('test_htgroup') do |tmpfile|
      tmpfile.close
      tmp_group = WEBrick::HTTPAuth::Htgroup.new(tmpfile.path)
      tmp_group.add 'superheroes', %w[spiderman batman]
      tmp_group.add 'supervillains', %w[joker]
      tmp_group.flush

      htgroup = WEBrick::HTTPAuth::Htgroup.new(tmpfile.path)
      assert_equal(htgroup.members('superheroes'), %w[spiderman batman])
      assert_equal(htgroup.members('supervillains'), %w[joker])
    end
  end
end
