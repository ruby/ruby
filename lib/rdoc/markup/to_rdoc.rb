require 'rdoc/markup/inline'

##
# Outputs RDoc markup as RDoc markup! (mostly)

class RDoc::Markup::ToRdoc < RDoc::Markup::Formatter

  attr_accessor :indent
  attr_reader :list_index
  attr_reader :list_type
  attr_reader :list_width
  attr_reader :prefix
  attr_reader :res

  def initialize
    super

    @markup.add_special(/\\[^\s]/, :SUPPRESSED_CROSSREF)

    @width = 78
    @prefix = ''

    init_tags

    @headings = {}
    @headings.default = []

    @headings[1] = ['= ',      '']
    @headings[2] = ['== ',     '']
    @headings[3] = ['=== ',    '']
    @headings[4] = ['==== ',   '']
    @headings[5] = ['===== ',  '']
    @headings[6] = ['====== ', '']
  end

  ##
  # Maps attributes to ANSI sequences

  def init_tags
    add_tag :BOLD, "<b>", "</b>"
    add_tag :TT,   "<tt>", "</tt>"
    add_tag :EM,   "<em>", "</em>"
  end

  def accept_blank_line blank_line
    @res << "\n"
  end

  def accept_heading heading
    use_prefix or @res << ' ' * @indent
    @res << @headings[heading.level][0]
    @res << attributes(heading.text)
    @res << @headings[heading.level][1]
    @res << "\n"
  end

  def accept_list_end list
    @list_index.pop
    @list_type.pop
    @list_width.pop
  end

  def accept_list_item_end list_item
    width = case @list_type.last
            when :BULLET then
              2
            when :NOTE, :LABEL then
              @res << "\n"
              2
            else
              bullet = @list_index.last.to_s
              @list_index[-1] = @list_index.last.succ
              bullet.length + 2
            end

    @indent -= width
  end

  def accept_list_item_start list_item
    bullet = case @list_type.last
             when :BULLET then
               '*'
             when :NOTE, :LABEL then
               attributes(list_item.label) + ":\n"
             else
               @list_index.last.to_s + '.'
             end

    case @list_type.last
    when :NOTE, :LABEL then
      @indent += 2
      @prefix = bullet + (' ' * @indent)
    else
      @prefix = (' ' * @indent) + bullet.ljust(bullet.length + 1)

      width = bullet.length + 1

      @indent += width
    end
  end

  def accept_list_start list
    case list.type
    when :BULLET then
      @list_index << nil
      @list_width << 1
    when :LABEL, :NOTE then
      @list_index << nil
      @list_width << 2
    when :LALPHA then
      @list_index << 'a'
      @list_width << list.items.length.to_s.length
    when :NUMBER then
      @list_index << 1
      @list_width << list.items.length.to_s.length
    when :UALPHA then
      @list_index << 'A'
      @list_width << list.items.length.to_s.length
    else
      raise RDoc::Error, "invalid list type #{list.type}"
    end

    @list_type << list.type
  end

  def accept_paragraph paragraph
    wrap attributes(paragraph.text)
  end

  def accept_raw raw
    @res << raw.parts.join("\n")
  end

  def accept_rule rule
    use_prefix or @res << ' ' * @indent
    @res << '-' * (@width - @indent)
    @res << "\n"
  end

  ##
  # Outputs +verbatim+ flush left and indented 2 columns

  def accept_verbatim verbatim
    indent = ' ' * (@indent + 2)

    lines = []
    current_line = []

    # split into lines
    verbatim.parts.each do |part|
      current_line << part

      if part == "\n" then
        lines << current_line
        current_line = []
      end
    end

    lines << current_line unless current_line.empty?

    # calculate margin
    indented = lines.select { |line| line != ["\n"] }
    margin = indented.map { |line| line.first.length }.min

    # flush left
    indented.each { |line| line[0][0...margin] = '' }

    # output
    use_prefix or @res << indent # verbatim is unlikely to have prefix
    @res << lines.shift.join

    lines.each do |line|
      @res << indent unless line == ["\n"]
      @res << line.join
    end

    @res << "\n"
  end

  def attributes text
    flow = @am.flow text.dup
    convert_flow flow
  end

  def end_accepting
    @res.join
  end

  def handle_special_SUPPRESSED_CROSSREF special
    special.text.sub(/\\/, '')
  end

  def start_accepting
    @res = [""]
    @indent = 0
    @prefix = nil

    @list_index = []
    @list_type  = []
    @list_width = []
  end

  def use_prefix
    prefix = @prefix
    @prefix = nil
    @res << prefix if prefix

    prefix
  end

  def wrap text
    return unless text && !text.empty?

    text_len = @width - @indent

    text_len = 20 if text_len < 20

    re = /^(.{0,#{text_len}})[ \n]/
    next_prefix = ' ' * @indent

    prefix = @prefix || next_prefix
    @prefix = nil

    @res << prefix

    while text.length > text_len
      if text =~ re then
        @res << $1
        text.slice!(0, $&.length)
      else
        @res << text.slice!(0, text_len)
      end

      @res << "\n" << next_prefix
    end

    if text.empty? then
      @res.pop
      @res.pop
    else
      @res << text
      @res << "\n"
    end
  end

end

