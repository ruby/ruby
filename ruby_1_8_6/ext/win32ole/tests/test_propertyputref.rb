require 'test/unit'
require 'win32ole'

class TestWIN32OLE_PROPERTYPUTREF < Test::Unit::TestCase
  def setup
    begin
      @sapi = WIN32OLE.new('SAPI.SpVoice')
    rescue WIN32OLERuntimeError
      @sapi = nil
    end
  end
  def test_sapi
    if @sapi
      new_id = @sapi.getvoices.item(2).Id
      @sapi.voice = @sapi.getvoices.item(2)
      assert_equal(new_id, @sapi.voice.Id)
    end
  end
end
