#!ruby

require_relative 'vpath'

class Checksum
  def initialize(vpath)
    @vpath = vpath
  end

  attr_reader :source, :target

  def source=(source)
    @source = source
    @checksum = File.basename(source, ".*") + ".chksum"
  end

  def target=(target)
    @target = target
  end

  def update?
    src = @vpath.read(@source)
    @len = src.length
    @sum = src.sum
    return false unless @vpath.search(File.method(:exist?), @target)
    begin
      data = @vpath.read(@checksum)
    rescue
      return false
    else
      return false unless data[/src="([0-9a-z_.-]+)",/, 1] == @source
      return false unless @len == data[/\blen=(\d+)/, 1].to_i
      return false unless @sum == data[/\bchecksum=(\d+)/, 1].to_i
      return true
    end
  end

  def update!
    open(@checksum, "wb") {|f|
      f.puts("src=\"#{@source}\", len=#{@len}, checksum=#{@sum}")
    }
  end

  def update
    return true if update?
    update! if ret = yield(self)
    ret
  end

  def copy(name)
    @vpath.open(name, "rb") {|f|
      IO.copy_stream(f, name)
    }
    true
  end

  def make(*args)
    system(@make, *args)
  end

  def def_options(opt = (require 'optparse'; OptionParser.new))
    @vpath.def_options(opt)
    opt.on("--make=PATH") {|v| @make = v}
    opt
  end

  def self.update(argv)
    k = new(VPath.new)
    k.source, k.target, *argv = k.def_options.parse(*argv)
    k.update {|k| yield(k, *argv)}
  end
end
