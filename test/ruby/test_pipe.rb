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

  def test_write
    bug2559 = '[ruby-core:27425]'
    a, b = IO.pipe
    begin
      a.close
      assert_raises(Errno::EPIPE, bug2559) do
        b.write("hi")
      end
    ensure
      a.close if !a.closed?
      b.close if !b.closed?
    end
  end
end
