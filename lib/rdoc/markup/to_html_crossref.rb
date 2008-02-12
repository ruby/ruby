require 'rdoc/markup/to_html'

##
# Subclass of the RDoc::Markup::ToHtml class that supports looking up words in
# the AllReferences list. Those that are found (like AllReferences in this
# comment) will be hyperlinked

class RDoc::Markup::ToHtmlCrossref < RDoc::Markup::ToHtml

  attr_accessor :context

  ##
  # We need to record the html path of our caller so we can generate
  # correct relative paths for any hyperlinks that we find

  def initialize(from_path, context, show_hash)
    super()

    # class names, variable names, or instance variables
    @markup.add_special(/(
                           # A::B.meth(**) (for operator in Fortran95)
                           \w+(::\w+)*[.\#]\w+(\([\.\w+\*\/\+\-\=\<\>]+\))?
                           # meth(**) (for operator in Fortran95)
                         | \#\w+(\([.\w\*\/\+\-\=\<\>]+\))?
                         | \b([A-Z]\w*(::\w+)*[.\#]\w+)  #    A::B.meth
                         | \b([A-Z]\w+(::\w+)*)          #    A::B
                         | \#\w+[!?=]?                   #    #meth_name
                         | \\?\b\w+([_\/\.]+\w+)*[!?=]?  #    meth_name
                         )/x,
                        :CROSSREF)

    @from_path = from_path
    @context = context
    @show_hash = show_hash

    @seen = {}
  end

  ##
  # We're invoked when any text matches the CROSSREF pattern
  # (defined in MarkUp). If we fine the corresponding reference,
  # generate a hyperlink. If the name we're looking for contains
  # no punctuation, we look for it up the module/class chain. For
  # example, HyperlinkHtml is found, even without the Generator::
  # prefix, because we look for it in module Generator first.

  def handle_special_CROSSREF(special)
    name = special.text

    return @seen[name] if @seen.include? name

    if name[0,1] == '#' then
      lookup = name[1..-1]
      name = lookup unless @show_hash
    else
      lookup = name
    end

    # Find class, module, or method in class or module.
    if /([A-Z]\w*)[.\#](\w+[!?=]?)/ =~ lookup then
      container = $1
      method = $2
      ref = @context.find_symbol container, method
    elsif /([A-Za-z]\w*)[.\#](\w+(\([\.\w+\*\/\+\-\=\<\>]+\))?)/ =~ lookup then
      container = $1
      method = $2
      ref = @context.find_symbol container, method
    else
      ref = @context.find_symbol lookup
    end

    out = if lookup =~ /^\\/ then
            $'
          elsif ref and ref.document_self then
            "<a href=\"#{ref.as_href(@from_path)}\">#{name}</a>"
          else
            name
          end

    @seen[name] = out

    out
  end

end

