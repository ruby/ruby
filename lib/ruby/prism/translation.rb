# frozen_string_literal: true
# :markup: markdown
#--
# rbs_inline: enabled

module Ruby::Prism
  # This module is responsible for converting the prism syntax tree into other
  # syntax trees.
  module Translation # steep:ignore
    autoload :Parser, "ruby/prism/translation/parser"
    autoload :ParserCurrent, "ruby/prism/translation/parser_current"
    autoload :Parser33, "ruby/prism/translation/parser_versions"
    autoload :Parser34, "ruby/prism/translation/parser_versions"
    autoload :Parser35, "ruby/prism/translation/parser_versions"
    autoload :Parser40, "ruby/prism/translation/parser_versions"
    autoload :Parser41, "ruby/prism/translation/parser_versions"
    autoload :Ripper, "ruby/prism/translation/ripper"
    autoload :RubyParser, "ruby/prism/translation/ruby_parser"
  end
end
