#!/usr/bin/ruby
require 'open-uri'

ConfigFiles = "http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=%s;hb=HEAD"
def ConfigFiles.download(name, dir = nil)
  data = open(self % name, &:read)
  file = dir ? File.join(dir, name) : name
  open(file, "wb", 0755) {|f| f.write(data)}
end

if $0 == __FILE__
  ARGV.each {|n| ConfigFiles.download(n)}
end
