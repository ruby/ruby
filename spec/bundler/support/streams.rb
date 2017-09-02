# frozen_string_literal: true
require "stringio"

def capture(*streams)
  streams.map!(&:to_s)
  begin
    result = StringIO.new
    streams.each {|stream| eval "$#{stream} = result" }
    yield
  ensure
    streams.each {|stream| eval("$#{stream} = #{stream.upcase}") }
  end
  result.string
end
