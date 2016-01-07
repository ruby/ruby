require 'optparse'
require_relative 'vpath'
require_relative 'colorize'

class AtomicWrite
  attr_accessor :vpath, :timestamp, :output, :compare :color

  def initialize
    @vpath = nil
    @timestamp = nil
    @output = nil
    @compare = nil
    @color = nil
  end

  def def_options(opt)
    opt.on('-t', '--timestamp[=PATH]') {|v| @timestamp = v || true}
    opt.on('-o', '--output=PATH') {|v| @output = v}
    opt.on('-c', '--[no-]if-change') {|v| @compare = v}
    opt.on('--color') {@color = true}
    @vpath.def_options(opt) if @vpath
    opt
  end

  def emit(result)
    output = @output
    if output
      update output, result
      stamp output
    else
      print result
    end
  end

  def update(output, result)
    color = Colorize.new(@color)
    unchanged = color.pass("unchanged")
    updated = color.fail("updated")
    vpath = @vpath || File
    if @compare and (vpath.open(output, "rb") {|f| f.read} rescue nil) == result
      puts "#{output} #{unchanged}"
      false
    else
      open(output, "wb") {|f| f.print result}
      puts "#{output} #{updated}"
      true
    end
  end

  def stamp(output, timestamp = @timestamp)
    if timestamp
      if timestamp == true
        dir, base = File.split(output)
        timestamp = File.join(dir, ".time." + base)
      end
      File.open(timestamp, 'a') {}
      File.utime(nil, nil, timestamp)
    end
  end
end
