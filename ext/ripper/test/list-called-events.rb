require 'ripper.so'

class R < Ripper
  def method_missing(mid, *args)
    puts mid
    args[0]
  end
  undef :warn
end

fname = (ARGV[0] || 'test/src_rb')
R.new(File.read(fname), fname, 1).parse
