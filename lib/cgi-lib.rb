#
# Get CGI String
#
# EXAMPLE:
# require "cgi-lib.rb"
# foo = CGI.new
# foo['field']   <== value of 'field'
# foo.keys       <== array of fields
# and foo has Hash class methods

# if running on Windows(IIS or PWS) then change cwd.
if ENV['SERVER_SOFTWARE'] =~ /^Microsoft-/ then
  Dir.chdir ENV['PATH_TRANSLATED'].sub(/[^\\]+$/, '')
end

require "delegate"

class CGI < SimpleDelegator

  attr("inputs")

  # original is CGI.pm
  def read_from_cmdline
    require "shellwords.rb"
    words = Shellwords.shellwords(if not ARGV.empty? then
                         ARGV.join(' ')
                       else
                         STDERR.print "(offline mode: enter name=value pairs on standard input)\n" if STDOUT.tty?
                         readlines.join(' ').gsub(/\n/, '')
                       end.gsub(/\\=/, '%3D').gsub(/\\&/, '%26'))

    if words.find{|x| x =~ /=/} then words.join('&') else words.join('+') end
  end
  
  # escape url encode
  def escape(str)
    str.gsub!(/[^a-zA-Z0-9_\-.]/n){ sprintf("%%%02X", $&.unpack("C")[0]) }
    str
  end

  # unescape url encoded
  def unescape(str)
    str.gsub! /\+/, ' '
    str.gsub!(/%([0-9a-fA-F]{2})/){ [$1.hex].pack("c") }
    str
  end
  module_function :escape, :unescape

  def initialize(input = $stdin)

    @inputs = {}
    case ENV['REQUEST_METHOD']
    when "GET"
      # exception messages should be printed to stdout.
      STDERR.reopen(STDOUT)

      ENV['QUERY_STRING'] or ""
    when "POST"
      # exception messages should be printed to stdout.
      STDERR.reopen(STDOUT)

      input.read ENV['CONTENT_LENGTH'].to_i
    else
      read_from_cmdline
    end.split(/&/).each do |x|
      key, val = x.split(/=/,2).collect{|x|unescape(x)}
      if @inputs.include?('key')
        @inputs[key] += "\0" + (val or "")
      else
        @inputs[key] = (val or "")
      end
    end

    super(@inputs)
  end

  def CGI.message(msg, title = "")
    print "Content-type: text/html\n\n"
    print "<html><head><title>"
    print title
    print "</title></head><body>\n"
    print msg
    print "</body></html>\n"
    TRUE
  end

  def CGI.error
    m = $!.to_s.dup
    m.gsub!(/&/, '&amp;')
    m.gsub!(/</, '&lt;')
    m.gsub!(/>/, '&gt;')
    msgs = ["<pre>ERROR: <strong>#{m}</strong>"]
    msgs << $@
    msgs << "</pre>"
    CGI.message(msgs.join("\n"), "ERROR")
    exit
  end
end
