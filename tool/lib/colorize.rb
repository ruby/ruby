# frozen-string-literal: true

class Colorize
  # call-seq:
  #   Colorize.new(colorize = nil)
  #   Colorize.new(color: color, colors_file: colors_file)
  def initialize(color = nil, opts = ((_, color = color, nil)[0] if Hash === color))
    @colors = @reset = nil
    @color = opts && opts[:color] || color
    if color or (color == nil && coloring?)
      if (%w[smso so].any? {|attr| /\A\e\[.*m\z/ =~ IO.popen("tput #{attr}", "r", :err => IO::NULL, &:read)} rescue nil)
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
    # color names
    "black"=>"30", "red"=>"31", "green"=>"32", "yellow"=>"33",
    "blue"=>"34", "magenta"=>"35", "cyan"=>"36", "white"=>"37",
    "bold"=>"1", "underline"=>"4", "reverse"=>"7",
    "bright_black"=>"90", "bright_red"=>"91", "bright_green"=>"92", "bright_yellow"=>"93",
    "bright_blue"=>"94", "bright_magenta"=>"95", "bright_cyan"=>"96", "bright_white"=>"97",

    # abstract decorations
    "pass"=>"green", "fail"=>"red;bold", "skip"=>"yellow;bold",
    "note"=>"bright_yellow", "notice"=>"bright_yellow", "info"=>"bright_magenta",
  }

  def coloring?
    STDOUT.tty? && (!(nc = ENV['NO_COLOR']) || nc.empty?)
  end

  # colorize.decorate(str, name = color_name)
  def decorate(str, name = @color)
    if coloring? and color = resolve_color(name)
      "#{@beg}#{color}m#{str}#{@reset}"
    else
      str
    end
  end

  def resolve_color(color = @color, seen = {}, colors = nil)
    return unless @colors
    color.to_s.gsub(/\b[a-z][\w ]+/) do |n|
      n.gsub!(/\W+/, "_")
      n.downcase!
      c = seen[n] and next c
      if colors
        c = colors[n]
      elsif (c = (tbl = @colors)[n] || (tbl = DEFAULTS)[n])
        colors = tbl
      else
        next n
      end
      seen[n] = resolve_color(c, seen, colors)
    end
  end

  DEFAULTS.each_key do |name|
    define_method(name) {|str|
      decorate(str, name)
    }
  end
end

if $0 == __FILE__
  colorize = Colorize.new(ARGV.shift)
  ARGV.each {|str| puts colorize.decorate(str)}
end
