# frozen_string_literal: true

require "stringio"

def capture(*args)
  opts = args.pop if args.last.is_a?(Hash)
  opts ||= {}

  args.map!(&:to_s)
  begin
    result = StringIO.new
    result.close if opts[:closed]
    args.each {|stream| eval "$#{stream} = result" }
    yield
  ensure
    args.each {|stream| eval("$#{stream} = #{stream.upcase}") }
  end
  result.string
end
