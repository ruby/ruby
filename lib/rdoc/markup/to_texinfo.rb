require 'rdoc/markup/formatter'
require 'rdoc/markup/fragments'
require 'rdoc/markup/inline'

require 'rdoc/markup'
require 'rdoc/markup/formatter'

##
# Convert SimpleMarkup to basic TexInfo format
#
# TODO: WTF is AttributeManager for?
#
class RDoc::Markup::ToTexInfo < RDoc::Markup::Formatter

  def start_accepting
    @text = []
  end

  def end_accepting
    @text.join("\n")
  end

  def accept_paragraph(attributes, text)
    @text << format(text)
  end

  def accept_verbatim(attributes, text)
    @text << "@verb{|#{format(text)}|}"
  end

  def accept_heading(attributes, text)
    heading = ['@majorheading', '@chapheading'][text.head_level - 1] || '@heading'
    @text << "#{heading} #{format(text)}"
  end

  def accept_list_start(attributes, text)
    @text << '@itemize @bullet'
  end

  def accept_list_end(attributes, text)
    @text << '@end itemize'
  end

  def accept_list_item(attributes, text)
    @text << "@item\n#{format(text)}"
  end

  def accept_blank_line(attributes, text)
    @text << "\n"
  end

  def accept_rule(attributes, text)
    @text << '-----'
  end

  def format(text)
    text.txt.
      gsub(/@/, "@@").
      gsub(/\{/, "@{").
      gsub(/\}/, "@}").
      # gsub(/,/, "@,"). # technically only required in cross-refs
      gsub(/\+([\w]+)\+/, "@code{\\1}").
      gsub(/\<tt\>([^<]+)\<\/tt\>/, "@code{\\1}").
      gsub(/\*([\w]+)\*/, "@strong{\\1}").
      gsub(/\<b\>([^<]+)\<\/b\>/, "@strong{\\1}").
      gsub(/_([\w]+)_/, "@emph{\\1}").
      gsub(/\<em\>([^<]+)\<\/em\>/, "@emph{\\1}")
  end
end
