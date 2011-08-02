require 'rdoc/markup/to_html'

##
# Subclass of the RDoc::Markup::ToHtml class that supports looking up words
# from a context.  Those that are found will be hyperlinked.

class RDoc::Markup::ToHtmlCrossref < RDoc::Markup::ToHtml

  ##
  # Regular expression to match class references
  #
  # 1. There can be a '\\' in front of text to suppress the cross-reference
  # 2. There can be a '::' in front of class names to reference from the
  #    top-level namespace.
  # 3. The method can be followed by parenthesis (not recommended)

  CLASS_REGEXP_STR = '\\\\?((?:\:{2})?[A-Z]\w*(?:\:\:\w+)*)'

  ##
  # Regular expression to match method references.
  #
  # See CLASS_REGEXP_STR

  METHOD_REGEXP_STR = '([a-z]\w*[!?=]?)(?:\([\w.+*/=<>-]*\))?'

  ##
  # Regular expressions matching text that should potentially have
  # cross-reference links generated are passed to add_special.  Note that
  # these expressions are meant to pick up text for which cross-references
  # have been suppressed, since the suppression characters are removed by the
  # code that is triggered.

  CROSSREF_REGEXP = /(
                      # A::B::C.meth
                      #{CLASS_REGEXP_STR}(?:[.#]|::)#{METHOD_REGEXP_STR}

                      # Stand-alone method (preceded by a #)
                      | \\?\##{METHOD_REGEXP_STR}

                      # Stand-alone method (preceded by ::)
                      | ::#{METHOD_REGEXP_STR}

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
                      # after the cross-reference is a space, sentence
                      # punctuation, tag start character, or attribute
                      # marker.
                      | #{CLASS_REGEXP_STR}(?=[\s\)\.\?\!\,\;<\000]|\z)

                      # Things that look like filenames
                      # The key thing is that there must be at least
                      # one special character (period, slash, or
                      # underscore).
                      | (?:\.\.\/)*[-\/\w]+[_\/\.][-\w\/\.]+

                      # Things that have markup suppressed
                      # Don't process things like '\<' in \<tt>, though.
                      # TODO: including < is a hack, not very satisfying.
                      | \\[^\s<]
                      )/x

  ##
  # Version of CROSSREF_REGEXP used when <tt>--hyperlink-all</tt> is specified.

  ALL_CROSSREF_REGEXP = /(
                      # A::B::C.meth
                      #{CLASS_REGEXP_STR}(?:[.#]|::)#{METHOD_REGEXP_STR}

                      # Stand-alone method
                      | \\?#{METHOD_REGEXP_STR}

                      # A::B::C
                      | #{CLASS_REGEXP_STR}(?=[\s\)\.\?\!\,\;<\000]|\z)

                      # Things that look like filenames
                      | (?:\.\.\/)*[-\/\w]+[_\/\.][-\w\/\.]+

                      # Things that have markup suppressed
                      | \\[^\s<]
                      )/x

  ##
  # RDoc::CodeObject for generating references

  attr_accessor :context

  ##
  # Should we show '#' characters on method references?

  attr_accessor :show_hash

  ##
  # Creates a new crossref resolver that generates links relative to +context+
  # which lives at +from_path+ in the generated files.  '#' characters on
  # references are removed unless +show_hash+ is true.  Only method names
  # preceded by '#' or '::' are hyperlinked, unless +hyperlink_all+ is true.

  def initialize(from_path, context, show_hash, hyperlink_all = false,
                 markup = nil)
    raise ArgumentError, 'from_path cannot be nil' if from_path.nil?
    super markup

    crossref_re = hyperlink_all ? ALL_CROSSREF_REGEXP : CROSSREF_REGEXP

    @markup.add_special crossref_re, :CROSSREF

    @from_path = from_path
    @context = context
    @show_hash = show_hash
    @hyperlink_all = hyperlink_all

    @seen = {}
  end

  ##
  # We're invoked when any text matches the CROSSREF pattern.  If we find the
  # corresponding reference, generate a hyperlink.  If the name we're looking
  # for contains no punctuation, we look for it up the module/class chain.
  # For example, ToHtml is found, even without the <tt>RDoc::Markup::</tt>
  # prefix, because we look for it in module Markup first.

  def handle_special_CROSSREF(special)
    name = special.text

    unless @hyperlink_all then
      # This ensures that words entirely consisting of lowercase letters will
      # not have cross-references generated (to suppress lots of erroneous
      # cross-references to "new" in text, for instance)
      return name if name =~ /\A[a-z]*\z/
    end

    return @seen[name] if @seen.include? name

    lookup = name

    name = name[1..-1] unless @show_hash if name[0, 1] == '#'

    # Find class, module, or method in class or module.
    #
    # Do not, however, use an if/elsif/else chain to do so.  Instead, test
    # each possible pattern until one matches.  The reason for this is that a
    # string like "YAML.txt" could be the txt() class method of class YAML (in
    # which case it would match the first pattern, which splits the string
    # into container and method components and looks up both) or a filename
    # (in which case it would match the last pattern, which just checks
    # whether the string as a whole is a known symbol).

    if /#{CLASS_REGEXP_STR}([.#]|::)#{METHOD_REGEXP_STR}/ =~ lookup then
      type = $2
      type = '' if type == '.'  # will find either #method or ::method
      method = "#{type}#{$3}"
      container = @context.find_symbol_module($1)
    elsif /^([.#]|::)#{METHOD_REGEXP_STR}/ =~ lookup then
      type = $1
      type = '' if type == '.'
      method = "#{type}#{$2}"
      container = @context
    else
      container = nil
    end

    if container then
      ref = container.find_local_symbol method

      unless ref || RDoc::TopLevel === container then
        ref = container.find_ancestor_local_symbol method
      end
    end

    ref = @context.find_symbol lookup unless ref
    ref = nil if RDoc::Alias === ref # external alias: can't link to it

    out = if lookup == '\\' then
            lookup
          elsif lookup =~ /^\\/ then
            # we remove the \ only in front of what we know:
            # other backslashes are treated later, only outside of <tt>
            ref ? $' : lookup
          elsif ref then
            if ref.document_self then
              "<a href=\"#{ref.as_href @from_path}\">#{name}</a>"
            else
              name
            end
          else
            lookup
          end

    @seen[lookup] = out

    out
  end

end

