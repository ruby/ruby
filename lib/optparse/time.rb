require 'optparse'
require 'parsedate'

OptionParser.accept(Time) do |s|
  begin
    Time::mktime(*ParseDate::parsedate(s)[0...6])
  rescue
    raise OptionParser::InvalidArgument, s
  end
end
