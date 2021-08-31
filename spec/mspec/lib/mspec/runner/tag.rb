class SpecTag
  attr_accessor :tag, :comment, :description

  def initialize(string = nil)
    parse(string) if string
  end

  def parse(string)
    m = /^([^()#:]+)(\(([^)]+)?\))?:(.*)$/.match string
    @tag, @comment, description = m.values_at(1, 3, 4) if m
    @description = unescape description
  end

  def unescape(str)
    return unless str
    if str[0] == ?" and str[-1] == ?"
      str[1..-2].gsub('\n', "\n")
    else
      str
    end
  end

  def escape(str)
    if str.include? "\n"
      %["#{str.gsub("\n", '\n')}"]
    else
      str
    end
  end

  def to_s
    "#{@tag}#{ "(#{@comment})" if @comment }:#{escape @description}"
  end

  def ==(o)
    @tag == o.tag and @comment == o.comment and @description == o.description
  end
end
