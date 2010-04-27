require 'rdoc/markup'

##
# Handle common directives that can occur in a block of text:
#
# : include : filename
#
# RDoc plugin authors can register additional directives to be handled through
# RDoc::Markup::PreProcess::register

class RDoc::Markup::PreProcess

  @registered = {}

  ##
  # Registers +directive+ as one handled by RDoc.  If a block is given the
  # directive will be replaced by the result of the block, otherwise the
  # directive will be removed from the processed text.

  def self.register directive, &block
    @registered[directive] = block
  end

  ##
  # Registered directives

  def self.registered
    @registered
  end

  ##
  # Creates a new pre-processor for +input_file_name+ that will look for
  # included files in +include_path+

  def initialize(input_file_name, include_path)
    @input_file_name = input_file_name
    @include_path = include_path
  end

  ##
  # Look for directives in a chunk of +text+.
  #
  # Options that we don't handle are yielded.  If the block returns false the
  # directive is restored to the text.  If the block returns nil or no block
  # was given the directive is handled according to the registered directives.
  # If a String was returned the directive is replaced with the string.
  #
  # If no matching directive was registered the directive is restored to the
  # text.
  #
  # If +code_object+ is given and the param is set as metadata on the
  # +code_object+.  See RDoc::CodeObject#metadata

  def handle text, code_object = nil
    text.gsub!(/^([ \t]*#?[ \t]*):(\w+):([ \t]*)(.+)?\n/) do
      next $& if $3.empty? and $4 and $4[0, 1] == ':'

      prefix    = $1
      directive = $2.downcase
      param     = $4

      case directive
      when 'include' then
        filename = param.split[0]
        include_file filename, prefix

      else
        result = yield directive, param if block_given?

        case result
        when nil then
          code_object.metadata[directive] = param if code_object
          if RDoc::Markup::PreProcess.registered.include? directive then
            handler = RDoc::Markup::PreProcess.registered[directive]
            result = handler.call directive, param if handler
          else
            result = "#{prefix}:#{directive}: #{param}\n"
          end
        when false then
          result = "#{prefix}:#{directive}: #{param}\n"
        end

        result
      end
    end

    text
  end

  ##
  # Include a file, indenting it correctly.

  def include_file(name, indent)
    if full_name = find_include_file(name) then
      content = if defined?(Encoding) then
                  File.binread full_name
                else
                  File.read full_name
                end
      # HACK determine content type and force encoding
      content = content.sub(/\A# .*coding[=:].*$/, '').lstrip

      # strip leading '#'s, but only if all lines start with them
      if content =~ /^[^#]/ then
        content.gsub(/^/, indent)
      else
        content.gsub(/^#?/, indent)
      end
    else
      warn "Couldn't find file to include '#{name}' from #{@input_file_name}"
      ''
    end
  end

  ##
  # Look for the given file in the directory containing the current file,
  # and then in each of the directories specified in the RDOC_INCLUDE path

  def find_include_file(name)
    to_search = [File.dirname(@input_file_name)].concat @include_path
    to_search.each do |dir|
      full_name = File.join(dir, name)
      stat = File.stat(full_name) rescue next
      return full_name if stat.readable?
    end
    nil
  end

end

