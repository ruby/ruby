require 'test/unit'
$:.replace([File.dirname(File.expand_path(__FILE__))] | $:)
require 'ut_eof'
require 'envutil'

class TestPipe < Test::Unit::TestCase
  include TestEOF
  def open_file(content)
    r, w = IO.pipe
    w << content
    w.close
    begin
      yield r
    ensure
      r.close
    end
  end
end
