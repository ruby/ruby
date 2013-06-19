require 'rdoc/rdoc'
require 'tmpdir'

Dir.mktmpdir('rdocbench-'){|d|
  dir = File.join(d, 'rdocbench')
  args = ARGV.dup
  args << '--op' << dir

  r = RDoc::RDoc.new
  r.document args
}
