=begin
= $RCSfile: telnets.rb,v $ -- SSL/TLS enhancement for Net::Telnet.

= Info
  'OpenSSL for Ruby 2' project
  Copyright (C) 2001 GOTOU YUUZOU <gotoyuzo@notwork.org>
  All rights reserved.

= Licence
  This program is licenced under the same licence as Ruby.
  (See the file 'LICENCE'.)

= Version
  $Id$
  
  2001/11/06: Contiributed to Ruby/OpenSSL project.

== class Net::Telnet

This class will initiate SSL/TLS session automaticaly if the server
sent OPT_STARTTLS. Some options are added for SSL/TLS.

  host = Net::Telnet::new({
           "Host"       => "localhost",
           "Port"       => "telnets",
           ## follows are new options.
           'CertFile'   => "user.crt",
           'KeyFile'    => "user.key",
           'CAFile'     => "/some/where/certs/casert.pem",
           'CAPath'     => "/some/where/caserts",
           'VerifyMode' => SSL::VERIFY_PEER,
           'VerifyCallback' => verify_proc
         })

Or, the new options ('Cert', 'Key' and 'CACert') are available from
Michal Rokos's OpenSSL module.

  cert_data = File.open("user.crt"){|io| io.read }
  pkey_data = File.open("user.key"){|io| io.read }
  cacert_data = File.open("your_ca.pem"){|io| io.read }
  host = Net::Telnet::new({
           "Host"       => "localhost",
           "Port"       => "telnets",
           'Cert'       => OpenSSL::X509::Certificate.new(cert_data)
           'Key'        => OpenSSL::PKey::RSA.new(pkey_data)
           'CACert'     => OpenSSL::X509::Certificate.new(cacert_data)
           'CAFile'     => "/some/where/certs/casert.pem",
           'CAPath'     => "/some/where/caserts",
           'VerifyMode' => SSL::VERIFY_PEER,
           'VerifyCallback' => verify_proc
         })

This class is expected to be a superset of usual Net::Telnet.
=end

require "net/telnet"
require "openssl"

module Net
  class Telnet
    attr_reader :ssl

    OPT_STARTTLS       =  46.chr # "\056" # "\x2e" # Start TLS
    TLS_FOLLOWS        =   1.chr # "\001" # "\x01" # FOLLOWS (for STARTTLS)

    alias preprocess_orig preprocess

    def ssl?; @ssl; end

    def preprocess(string)
      # combine CR+NULL into CR
      string = string.gsub(/#{CR}#{NULL}/no, CR) if @options["Telnetmode"]

      # combine EOL into "\n"
      string = string.gsub(/#{EOL}/no, "\n") unless @options["Binmode"]

      string.gsub(/#{IAC}(
                   [#{IAC}#{AO}#{AYT}#{DM}#{IP}#{NOP}]|
                   [#{DO}#{DONT}#{WILL}#{WONT}][#{OPT_BINARY}-#{OPT_EXOPL}]|
                   #{SB}[#{OPT_BINARY}-#{OPT_EXOPL}]
                     (#{IAC}#{IAC}|[^#{IAC}])+#{IAC}#{SE}
                 )/xno) do
        if    IAC == $1  # handle escaped IAC characters
          IAC
        elsif AYT == $1  # respond to "IAC AYT" (are you there)
          self.write("nobody here but us pigeons" + EOL)
          ''
        elsif DO[0] == $1[0]  # respond to "IAC DO x"
          if    OPT_BINARY[0] == $1[1]
            @telnet_option["BINARY"] = true
            self.write(IAC + WILL + OPT_BINARY)
          elsif OPT_STARTTLS[0] == $1[1]
            self.write(IAC + WILL + OPT_STARTTLS)
            self.write(IAC + SB + OPT_STARTTLS + TLS_FOLLOWS + IAC + SE)
          else
            self.write(IAC + WONT + $1[1..1])
          end
          ''
        elsif DONT[0] == $1[0]  # respond to "IAC DON'T x" with "IAC WON'T x"
          self.write(IAC + WONT + $1[1..1])
          ''
        elsif WILL[0] == $1[0]  # respond to "IAC WILL x"
          if    OPT_BINARY[0] == $1[1]
            self.write(IAC + DO + OPT_BINARY)
          elsif OPT_ECHO[0] == $1[1]
            self.write(IAC + DO + OPT_ECHO)
          elsif OPT_SGA[0]  == $1[1]
            @telnet_option["SGA"] = true
            self.write(IAC + DO + OPT_SGA)
          else
            self.write(IAC + DONT + $1[1..1])
          end
          ''
        elsif WONT[0] == $1[0]  # respond to "IAC WON'T x"
          if    OPT_ECHO[0] == $1[1]
            self.write(IAC + DONT + OPT_ECHO)
          elsif OPT_SGA[0]  == $1[1]
            @telnet_option["SGA"] = false
            self.write(IAC + DONT + OPT_SGA)
          else
            self.write(IAC + DONT + $1[1..1])
          end
          ''
        elsif SB[0] == $1[0]    # respond to "IAC SB xxx IAC SE"
          if    OPT_STARTTLS[0] == $1[1] && TLS_FOLLOWS[0] == $2[0]
            @sock = OpenSSL::SSL::SSLSocket.new(@sock)
            @sock.cert            = @options['Cert'] unless @sock.cert
            @sock.key             = @options['Key'] unless @sock.key
            @sock.ca_cert         = @options['CACert']
            @sock.ca_file         = @options['CAFile']
            @sock.ca_path         = @options['CAPath']
            @sock.timeout         = @options['Timeout']
            @sock.verify_mode     = @options['VerifyMode']
            @sock.verify_callback = @options['VerifyCallback']
            @sock.verify_depth    = @options['VerifyDepth']
            @sock.connect
            @ssl = true
          end
          ''
        else
          ''
        end
      end
    end # preprocess
    
    alias waitfor_org waitfor

    def waitfor(options)
      time_out = @options["Timeout"]
      waittime = @options["Waittime"]

      if options.kind_of?(Hash)
        prompt   = if options.has_key?("Match")
                     options["Match"]
                   elsif options.has_key?("Prompt")
                     options["Prompt"]
                   elsif options.has_key?("String")
                     Regexp.new( Regexp.quote(options["String"]) )
                   end
        time_out = options["Timeout"]  if options.has_key?("Timeout")
        waittime = options["Waittime"] if options.has_key?("Waittime")
      else
        prompt = options
      end

      if time_out == false
        time_out = nil
      end

      line = ''
      buf = ''
      @rest = '' unless @rest

      until(prompt === line and not IO::select([@sock], nil, nil, waittime))
        unless IO::select([@sock], nil, nil, time_out)
          raise TimeoutError, "timed-out; wait for the next data"
        end
        begin
          c = @rest + @sock.sysread(1024 * 1024)
          @dumplog.log_dump('<', c) if @options.has_key?("Dump_log")
          if @options["Telnetmode"]   
            pos = 0
            catch(:next){
              while true
                case c[pos]
                when IAC[0]
                  case c[pos+1]
                  when DO[0], DONT[0], WILL[0], WONT[0]
                    throw :next unless c[pos+2]
                    pos += 3
                  when SB[0]
                    ret = detect_sub_negotiation(c, pos)
                    throw :next unless ret
                    pos = ret
                  when nil
                    throw :next
                  else
                    pos += 2
                  end
                when nil
                  throw :next
                else
                  pos += 1
                end
              end
            }

            buf = preprocess(c[0...pos])
            @rest = c[pos..-1]
          end
          @log.print(buf) if @options.has_key?("Output_log")
          line.concat(buf)
          yield buf if block_given?   
        rescue EOFError # End of file reached
          if line == ''
            line = nil
            yield nil if block_given? 
          end
          break
        end
      end
      line
    end

    private

    def detect_sub_negotiation(data, pos)
      return nil if data.length < pos+6  # IAC SB x param IAC SE
      pos += 3
      while true
        case data[pos]
        when IAC[0]
          if data[pos+1] == SE[0]
            pos += 2
            return pos
          else
            pos += 2
          end
        when nil
          return nil
        else
          pos += 1
        end
      end
    end

  end
end
