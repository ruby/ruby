require_relative 'vpath'
require_relative 'colorize'

class Output
  attr_reader :path, :vpath

  def initialize
    @path = @timestamp = @ifchange = @color = nil
    @vpath = VPath.new
  end

  def def_options(opt)
    opt.separator("  Output common options:")
    opt.on('-o', '--output=PATH') {|v| @path = v}
    opt.on('-t', '--timestamp[=PATH]') {|v| @timestamp = v || true}
    opt.on('-c', '--[no-]if-change') {|v| @ifchange = v}
    opt.on('--color') {@color = true}
    @vpath.def_options(opt)
  end

  def write(data, overwrite: false, create_only: false)
    unless @path
      $stdout.print data
      return true
    end
    color = Colorize.new(@color)
    unchanged = color.pass("unchanged")
    updated = color.fail("updated")
    outpath = nil

    if (@ifchange or overwrite or create_only) and (@vpath.open(@path, "rb") {|f|
      outpath = f.path
      if @ifchange or create_only
        original = f.read
        (@ifchange and original == data) or (create_only and !original.empty?)
      end
    } rescue false)
      puts "#{outpath} #{unchanged}"
      written = false
    else
      unless overwrite and outpath and (File.binwrite(outpath, data) rescue nil)
        File.binwrite(outpath = @path, data)
      end
      puts "#{outpath} #{updated}"
      written = true
    end
    if timestamp = @timestamp
      if timestamp == true
        dir, base = File.split(@path)
        timestamp = File.join(dir, ".time." + base)
      end
      File.binwrite(timestamp, '')
      File.utime(nil, nil, timestamp)
    end
    written
  end
end
