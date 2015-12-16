# frozen_string_literal: false
require 'test/unit'
require_relative 'ut_eof'

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
  class WithConversion < self
    def open_file(content)
      r, w = IO.pipe
      w << content
      w.close
      r.set_encoding("us-ascii:utf-8")
      begin
        yield r
      ensure
        r.close
      end
    end
  end
end
