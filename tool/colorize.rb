# frozen-string-literal: true

class Colorize
  def initialize(color = nil)
    @colors = @reset = nil
    if color or (color == nil && STDOUT.tty?)
      if (/\A\e\[.*m\z/ =~ IO.popen("tput smso", "r", err: IO::NULL, &:read) rescue nil)
        @beg = "\e["
        @colors = (colors = ENV['TEST_COLORS']) ? Hash[colors.scan(/(\w+)=([^:\n]*)/)] : {}
        @reset = "#{@beg}m"
      end
    end
    self
  end

  DEFAULTS = {
    "pass"=>"32;1", "fail"=>"31;1", "skip"=>"33;1",
    "black"=>"30", "red"=>"31", "green"=>"32", "yellow"=>"33",
    "blue"=>"34", "magenta"=>"35", "cyan"=>"36", "white"=>"37",
  }

  def decorate(str, name)
    if @colors and color = (@colors[name] || DEFAULTS[name])
      "#{@beg}#{color}m#{str}#{@reset}"
    else
      str
    end
  end

  DEFAULTS.each_key do |name|
    define_method(name) {|str|
      decorate(str, name)
    }
  end
end

if $0 == __FILE__
  colorize = Colorize.new
  col = ARGV.shift
  ARGV.each {|str| puts colorize.decorate(str, col)}
end
