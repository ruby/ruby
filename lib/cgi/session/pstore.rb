require 'cgi/session'
require 'pstore'

class CGI
  class Session
    def []=(key, val)
      unless @write_lock
	@write_lock = true
      end
      unless @data
	@data = @dbman.restore
      end
      #@data[key] = String(val)
      @data[key] = val
    end

    class PStore
      def check_id(id)
	/[^0-9a-zA-Z]/ =~ id.to_s ? false : true
      end

      def initialize session, option={}
	dir = option['tmpdir'] || ENV['TMP'] || '/tmp'
	prefix = option['prefix'] || ''
	id = session.session_id
	unless check_id(id)
	  raise ArgumentError, "session_id `%s' is invalid" % id
	end
	path = dir+"/"+prefix+id
	path.untaint
	unless File::exist? path
	  @hash = {}
	end
	@p = ::PStore.new path 
      end

      def restore
	unless @hash
	  @p.transaction do
	    begin
	      @hash = @p['hash']
	    rescue
	      @hash = {}
	    end
	  end
	end
	@hash
      end

      def update 
	@p.transaction do
	    @p['hash'] = @hash
	end
      end

      def close
	update
      end

      def delete
	path = @p.path
	File::unlink path
      end

    end
  end
end

if $0 == __FILE__
  STDIN.reopen("/dev/null")
  cgi = CGI.new
  session = CGI::Session.new cgi, 'database_manager' => CGI::Session::PStore
  session['key'] = {'k' => 'v'}
  puts session['key'].class
  fail unless Hash === session['key']
  puts session['key'].inspect
  fail unless session['key'].inspect == '{"k"=>"v"}'
end
