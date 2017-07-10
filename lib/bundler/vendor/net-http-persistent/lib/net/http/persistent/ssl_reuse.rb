##
# This Net::HTTP subclass adds SSL session reuse and Server Name Indication
# (SNI) RFC 3546.
#
# DO NOT DEPEND UPON THIS CLASS
#
# This class is an implementation detail and is subject to change or removal
# at any time.

class Bundler::Persistent::Net::HTTP::Persistent::SSLReuse < Net::HTTP

  @is_proxy_class = false
  @proxy_addr = nil
  @proxy_port = nil
  @proxy_user = nil
  @proxy_pass = nil

  def initialize address, port = nil # :nodoc:
    super

    @ssl_session = nil
  end

  ##
  # From ruby trunk r33086 including http://redmine.ruby-lang.org/issues/5341

  def connect # :nodoc:
    D "opening connection to #{conn_address()}..."
    s = timeout(@open_timeout) { TCPSocket.open(conn_address(), conn_port()) }
    D "opened"
    if use_ssl?
      ssl_parameters = Hash.new
      iv_list = instance_variables
      SSL_ATTRIBUTES.each do |name|
        ivname = "@#{name}".intern
        if iv_list.include?(ivname) and
           value = instance_variable_get(ivname)
          ssl_parameters[name] = value
        end
      end
      unless @ssl_context then
        @ssl_context = OpenSSL::SSL::SSLContext.new
        @ssl_context.set_params(ssl_parameters)
      end
      s = OpenSSL::SSL::SSLSocket.new(s, @ssl_context)
      s.sync_close = true
    end
    @socket = Net::BufferedIO.new(s)
    @socket.read_timeout = @read_timeout
    @socket.continue_timeout = @continue_timeout if
      @socket.respond_to? :continue_timeout
    @socket.debug_output = @debug_output
    if use_ssl?
      begin
        if proxy?
          @socket.writeline sprintf('CONNECT %s:%s HTTP/%s',
                                    @address, @port, HTTPVersion)
          @socket.writeline "Host: #{@address}:#{@port}"
          if proxy_user
            credential = ["#{proxy_user}:#{proxy_pass}"].pack('m')
            credential.delete!("\r\n")
            @socket.writeline "Proxy-Authorization: Basic #{credential}"
          end
          @socket.writeline ''
          Net::HTTPResponse.read_new(@socket).value
        end
        s.session = @ssl_session if @ssl_session
        # Server Name Indication (SNI) RFC 3546
        s.hostname = @address if s.respond_to? :hostname=
        timeout(@open_timeout) { s.connect }
        if @ssl_context.verify_mode != OpenSSL::SSL::VERIFY_NONE
          s.post_connection_check(@address)
        end
        @ssl_session = s.session
      rescue => exception
        D "Conn close because of connect error #{exception}"
        @socket.close if @socket and not @socket.closed?
        raise exception
      end
    end
    on_connect
  end if RUBY_VERSION > '1.9'

  ##
  # From ruby_1_8_7 branch r29865 including a modified
  # http://redmine.ruby-lang.org/issues/5341

  def connect # :nodoc:
    D "opening connection to #{conn_address()}..."
    s = timeout(@open_timeout) { TCPSocket.open(conn_address(), conn_port()) }
    D "opened"
    if use_ssl?
      unless @ssl_context.verify_mode
        warn "warning: peer certificate won't be verified in this SSL session"
        @ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      s = OpenSSL::SSL::SSLSocket.new(s, @ssl_context)
      s.sync_close = true
    end
    @socket = Net::BufferedIO.new(s)
    @socket.read_timeout = @read_timeout
    @socket.debug_output = @debug_output
    if use_ssl?
      if proxy?
        @socket.writeline sprintf('CONNECT %s:%s HTTP/%s',
                                  @address, @port, HTTPVersion)
        @socket.writeline "Host: #{@address}:#{@port}"
        if proxy_user
          credential = ["#{proxy_user}:#{proxy_pass}"].pack('m')
          credential.delete!("\r\n")
          @socket.writeline "Proxy-Authorization: Basic #{credential}"
        end
        @socket.writeline ''
        Net::HTTPResponse.read_new(@socket).value
      end
      s.session = @ssl_session if @ssl_session
      s.connect
      if @ssl_context.verify_mode != OpenSSL::SSL::VERIFY_NONE
        s.post_connection_check(@address)
      end
      @ssl_session = s.session
    end
    on_connect
  end if RUBY_VERSION < '1.9'

  private :connect

end

