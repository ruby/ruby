require 'test/unit'
$:.replace([File.dirname(File.expand_path(__FILE__))] | $:)
require 'ut_eof'
require 'envutil'

$KCODE = 'none'

class TestPipe < Test::Unit::TestCase
  include TestEOF
  def open_file(content)
    f = IO.popen("echo -n #{content}")
    yield f
  end
end
