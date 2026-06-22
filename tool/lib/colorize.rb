# frozen-string-literal: true

# Decorate TTY output using ANSI Select Graphic Rendition control
# sequences.
class Colorize
  # call-seq:
  #   Colorize.new(colorize = nil)
  #   Colorize.new(color: color, colors_file: colors_file)
  #
  # Creates and load color settings.
  def initialize(_color = nil, color: _color, colors_file: nil)
    @colors = nil
    @color = color
    if color or (color == nil && coloring?)
      if (%w[smso so].any? {|attr| /\A\e\[.*m\z/ =~ IO.popen("tput #{attr}", "r", err: IO::NULL, &:read)} rescue nil)
        @beg = "\e["
        colors = (colors = ENV['TEST_COLORS']) ? Hash[colors.scan(COLORS_PATTERN)] : {}
        if colors_file
          begin
            File.read(colors_file).scan(COLORS_PATTERN) do |n, c|
              colors[n] ||= c
            end
          rescue Errno::ENOENT
          end
        end
        @colors = colors
      end
    end
    self
  end

  COLORS_PATTERN = /(\w+)=([^:\n]*)/
  private_constant :COLORS_PATTERN

  DEFAULTS = {
    # color names
    "black"=>"30", "red"=>"31", "green"=>"32", "yellow"=>"33",
    "blue"=>"34", "magenta"=>"35", "cyan"=>"36", "white"=>"37",
    "bold"=>"1", "faint"=>"2", "underline"=>"4", "reverse"=>"7",
    "bright_black"=>"90", "bright_red"=>"91", "bright_green"=>"92", "bright_yellow"=>"93",
    "bright_blue"=>"94", "bright_magenta"=>"95", "bright_cyan"=>"96", "bright_white"=>"97",
    "bg_black"=>"40", "bg_red"=>"41", "bg_green"=>"42", "bg_yellow"=>"43",
    "bg_blue"=>"44", "bg_magenta"=>"45", "bg_cyan"=>"46", "bg_white"=>"47",
    "bg_bright_black"=>"100", "bg_bright_red"=>"101",
    "bg_bright_green"=>"102", "bg_bright_yellow"=>"103",
    "bg_bright_blue"=>"104", "bg_bright_magenta"=>"105",
    "bg_bright_cyan"=>"106", "bg_bright_white"=>"107",

    # abstract decorations
    "pass"=>"green", "fail"=>"red;bold", "skip"=>"yellow;bold",
    "note"=>"bright_yellow", "notice"=>"bright_yellow", "info"=>"bright_magenta",
  }.freeze
  private_constant :DEFAULTS

  # colorize.decorate(str, name = color_name)
  def decorate(str, name = @color)
    if coloring? and color = resolve_color(name)
      "#{@beg}#{color}m#{str}#{reset_color(color)}"
    else
      str
    end
  end

  DEFAULTS.each_key do |name|
    define_method(name) {|str|
      decorate(str, name)
    }
  end

  private

  def coloring?
    STDOUT.tty? && (!(nc = ENV['NO_COLOR']) || nc.empty?)
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

  def reset_color(colors)
    resets = []
    colors.scan(/\G;*\K(?:[34]8;(?:5;\d+|2(?:;\d+){3})|\d+)/) do |c|
      case c
      when '1', '2'
        resets << '22'
      when '4'
        resets << '24'
      when '7'
        resets << '27'
      when /\A[39]\d(?:;|\z)/
        resets << '39'
      when /\A(?:4|10)\d(?:;|\z)/
        resets << '49'
      end
    end
    "#{@beg}#{resets.reverse.join(';')}m"
  end
end

if $0 == __FILE__
  colorize = Colorize.new(ARGV.shift)
  ARGV.each {|str| puts colorize.decorate(str)}
end
