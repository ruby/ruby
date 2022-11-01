require_relative 'vpath'
require_relative 'colorize'

class Output
  attr_reader :path, :vpath

  def initialize
    @path = @timestamp = @ifchange = @color = nil
    @vpath = VPath.new
  end

  def def_options(opt)
    opt.on('-o', '--output=PATH') {|v| @path = v}
    opt.on('-t', '--timestamp[=PATH]') {|v| @timestamp = v || true}
    opt.on('-c', '--[no-]if-change') {|v| @ifchange = v}
    opt.on('--color') {@color = true}
    @vpath.def_options(opt)
  end

  def write(data)
    unless @path
      $stdout.print data
      return true
    end
    color = Colorize.new(@color)
    unchanged = color.pass("unchanged")
    updated = color.fail("updated")

    if @ifchange and (@vpath.read(@path, "rb") == data rescue false)
      puts "#{@path} #{unchanged}"
      written = false
    else
      File.binwrite(@path, data)
      puts "#{@path} #{updated}"
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
