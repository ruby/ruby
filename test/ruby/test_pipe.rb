require 'test/unit'
require 'ut_eof'
require 'envutil'

$KCODE = 'none'

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
