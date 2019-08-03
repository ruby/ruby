# frozen-string-literal: true

class Colorize
  def initialize(color = nil, opts = ((_, color = color, nil)[0] if Hash === color))
    @colors = @reset = nil
    if color or (color == nil && STDOUT.tty?)
      if (/\A\e\[.*m\z/ =~ IO.popen("tput smso", "r", :err => IO::NULL, &:read) rescue nil)
        @beg = "\e["
        colors = (colors = ENV['TEST_COLORS']) ? Hash[colors.scan(/(\w+)=([^:\n]*)/)] : {}
        if opts and colors_file = opts[:colors_file]
          begin
            File.read(colors_file).scan(/(\w+)=([^:\n]*)/) do |n, c|
              colors[n] ||= c
            end
          rescue Errno::ENOENT
          end
        end
        @colors = colors
        @reset = "#{@beg}m"
      end
    end
    self
  end

  DEFAULTS = {
    "pass"=>"32", "fail"=>"31;1", "skip"=>"33;1",
    "black"=>"30", "red"=>"31", "green"=>"32", "yellow"=>"33",
    "blue"=>"34", "magenta"=>"35", "cyan"=>"36", "white"=>"37",
    "bold"=>"1", "underline"=>"4", "reverse"=>"7",
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
