#
# Create files
#

require 'tempfile'

max = 50_000
file = './tmpfile_of_bm_io_file_create'

max.times{
  #f = Tempfile.new('yarv-benchmark')
  f = open(file, 'w')
  f.close#(true)
}
File.unlink(file)

