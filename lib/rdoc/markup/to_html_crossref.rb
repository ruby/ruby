require 'rdoc/markup/to_html'

##
# Subclass of the RDoc::Markup::ToHtml class that supports looking up words in
# the AllReferences list. Those that are found (like AllReferences in this
# comment) will be hyperlinked

class RDoc::Markup::ToHtmlCrossref < RDoc::Markup::ToHtml

  attr_accessor :context

  # Regular expressions to match class and method references.
  # 
  # 1.) There can be a '\' in front of text to suppress
  #     any cross-references (note, however, that the single '\'
  #     is written as '\\\\' in order to escape it twice, once
  #     in the Ruby String literal and once in the regexp).
  # 2.) There can be a '::' in front of class names to reference
  #     from the top-level namespace.
  # 3.) The method can be followed by parenthesis,
  #     which may or may not have things inside (this
  #     apparently is allowed for Fortran 95, but I also think that this
  #     is a good idea for Ruby, as it is very reasonable to want to
  #     reference a call with arguments).
  #
  # NOTE: In order to support Fortran 95 properly, the [A-Z] below
  # should be changed to [A-Za-z].  This slows down rdoc significantly,
  # however, and the Fortran 95 support is broken in any case due to
  # the return in handle_special_CROSSREF if the token consists
  # entirely of lowercase letters.
  #
  # The markup/cross-referencing engine needs a rewrite for
  # Fortran 95 to be supported properly.
  CLASS_REGEXP_STR = '\\\\?((?:\:{2})?[A-Z]\w*(?:\:\:\w+)*)'
  METHOD_REGEXP_STR = '(\w+[!?=]?)(?:\([\.\w+\*\/\+\-\=\<\>]*\))?'

  # Regular expressions matching text that should potentially have
  # cross-reference links generated are passed to add_special.
  # Note that these expressions are meant to pick up text for which
  # cross-references have been suppressed, since the suppression
  # characters are removed by the code that is triggered.
  CROSSREF_REGEXP = /(
                      # A::B::C.meth
                      #{CLASS_REGEXP_STR}[\.\#]#{METHOD_REGEXP_STR}

                      # Stand-alone method (proceeded by a #)
                      | \\?\##{METHOD_REGEXP_STR}

                      # A::B::C
                      # The stuff after CLASS_REGEXP_STR is a
                      # nasty hack.  CLASS_REGEXP_STR unfortunately matches
                      # words like dog and cat (these are legal "class"
                      # names in Fortran 95).  When a word is flagged as a
                      # potential cross-reference, limitations in the markup
                      # engine suppress other processing, such as typesetting.
                      # This is particularly noticeable for contractions.
                      # In order that words like "can't" not
                      # be flagged as potential cross-references, only
                      # flag potential class cross-references if the character
                      # after the cross-referece is a space or sentence
                      # punctuation.
                      | #{CLASS_REGEXP_STR}(?=[\s\)\.\?\!\,\;]|\z)

                      # Things that look like filenames
                      # The key thing is that there must be at least
                      # one special character (period, slash, or
                      # underscore).
                      | [\/\w]+[_\/\.][\w\/\.]+

                      # Things that have markup suppressed
                      | \\[^\s]
                      )/x

  ##
  # We need to record the html path of our caller so we can generate
  # correct relative paths for any hyperlinks that we find

  def initialize(from_path, context, show_hash)
    raise ArgumentError, 'from_path cannot be nil' if from_path.nil?
    super()

    @markup.add_special(CROSSREF_REGEXP, :CROSSREF)

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

    # This ensures that words entirely consisting of lowercase letters will
    # not have cross-references generated (to suppress lots of
    # erroneous cross-references to "new" in text, for instance)
    return name if name =~ /\A[a-z]*\z/

    return @seen[name] if @seen.include? name

    if name[0, 1] == '#' then
      lookup = name[1..-1]
      name = lookup unless @show_hash
    else
      lookup = name
    end


    # Find class, module, or method in class or module.
    #
    # Do not, however, use an if/elsif/else chain to do so.  Instead, test
    # each possible pattern until one matches.  The reason for this is that a
    # string like "YAML.txt" could be the txt() class method of class YAML (in
    # which case it would match the first pattern, which splits the string
    # into container and method components and looks up both) or a filename
    # (in which case it would match the last pattern, which just checks
    # whether the string as a whole is a known symbol).

    if /#{CLASS_REGEXP_STR}[\.\#]#{METHOD_REGEXP_STR}/ =~ lookup then
      container = $1
      method = $2
      ref = @context.find_symbol container, method
    end

    ref = @context.find_symbol lookup unless ref

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
