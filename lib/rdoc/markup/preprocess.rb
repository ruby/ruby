require 'rdoc/markup'

##
# Handle common directives that can occur in a block of text:
#
# : include : filename

class RDoc::Markup::PreProcess

  ##
  # Creates a new pre-processor for +input_file_name+ that will look for
  # included files in +include_path+

  def initialize(input_file_name, include_path)
    @input_file_name = input_file_name
    @include_path = include_path
  end

  ##
  # Look for common options in a chunk of text. Options that we don't handle
  # are yielded to the caller.

  def handle(text)
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
        result = yield directive, param
        result = "#{prefix}:#{directive}: #{param}\n" unless result
        result
      end
    end
  end

  private

  ##
  # Include a file, indenting it correctly.

  def include_file(name, indent)
    if full_name = find_include_file(name) then
      content = File.read full_name

      # strip leading '#'s, but only if all lines start with them
      if content =~ /^[^#]/ then
        content.gsub(/^/, indent)
      else
        content.gsub(/^#?/, indent)
      end
    else
      $stderr.puts "Couldn't find file to include '#{name}' from #{@input_file_name}"
      ''
    end
  end

  ##
  # Look for the given file in the directory containing the current file,
  # and then in each of the directories specified in the RDOC_INCLUDE path

  def find_include_file(name)
    to_search = [ File.dirname(@input_file_name) ].concat @include_path
    to_search.each do |dir|
      full_name = File.join(dir, name)
      stat = File.stat(full_name) rescue next
      return full_name if stat.readable?
    end
    nil
  end

end

