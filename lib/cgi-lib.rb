#!/usr/local/bin/ruby
#
# Get CGI String
#
# EXAMPLE:
# require "cgi-lib.rb"
# foo = CGI.new
# foo['field']   <== value of 'field'
# foo.keys       <== array of fields
# foo.inputs     <== hash of { <field> => <value> }

class CGI
  attr("inputs")
  
  def initialize
    str = if ENV['REQUEST_METHOD'] == "GET"
            ENV['QUERY_STRING']
         elsif ENV['REQUEST_METHOD'] == "POST"
           $stdin.read ENV['CONTENT_LENGTH'].to_i
         else
           ""
         end
    arr = str.split(/&/)
    @inputs = {}
    arr.each do |x|
      x.gsub!(/\+/, ' ')
      key, val = x.split(/=/, 2)
      val = "" unless val
      
      key.gsub!(/%(..)/) { [$1.hex].pack("c") }
      val.gsub!(/%(..)/) { [$1.hex].pack("c") }

      @inputs[key] += "\0" if @inputs[key]
      @inputs[key] += val
    end
  end

  def keys
    @inputs.keys
  end

  def [](key)
    @inputs[key]
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

end
