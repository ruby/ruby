=begin

== NAME

net/telnet.rb - simple telnet client library

Version 1.6.0

Wakou Aoyama <wakou@fsinet.or.jp>


=== MAKE NEW TELNET OBJECT

  host = Net::Telnet::new({
           "Binmode"    => false,        # default: false
           "Host"       => "localhost",  # default: "localhost"
           "Output_log" => "output_log", # default: nil (no output)
           "Dump_log"   => "dump_log",   # default: nil (no output)
           "Port"       => 23,           # default: 23
           "Prompt"     => /[$%#>] \z/n, # default: /[$%#>] \z/n
           "Telnetmode" => true,         # default: true
           "Timeout"    => 10,           # default: 10
             # if ignore timeout then set "Timeout" to false.
           "Waittime"   => 0,            # default: 0
           "Proxy"      => proxy         # default: nil
                           # proxy is Net::Telnet or IO object
         })

Telnet object has socket class methods.

if set "Telnetmode" option to false. not telnet command interpretation.
"Waittime" is time to confirm "Prompt". There is a possibility that
the same character as "Prompt" is included in the data, and, when
the network or the host is very heavy, the value is enlarged.


=== STATUS OUTPUT

  host = Net::Telnet::new({"Host" => "localhost"}){|c| print c }

connection status output.

example:

  Trying localhost...
  Connected to localhost.


=== WAIT FOR MATCH

  line = host.waitfor(/match/)
  line = host.waitfor({"Match"   => /match/,
                       "String"  => "string",
                       "Timeout" => secs})
                         # if ignore timeout then set "Timeout" to false.

if set "String" option, then Match == Regexp.new(quote("string"))


==== REALTIME OUTPUT

  host.waitfor(/match/){|c| print c }
  host.waitfor({"Match"   => /match/,
                "String"  => "string",
                "Timeout" => secs}){|c| print c}

of cource, set sync=true or flush is necessary.


=== SEND STRING AND WAIT PROMPT

  line = host.cmd("string")
  line = host.cmd({"String" => "string",
                   "Match" => /[$%#>] \z/n,
                   "Timeout" => 10})


==== REALTIME OUTPUT

  host.cmd("string"){|c| print c }
  host.cmd({"String" => "string",
            "Match" => /[$%#>] \z/n,
            "Timeout" => 10}){|c| print c }

of cource, set sync=true or flush is necessary.


=== SEND STRING

  host.print("string")
  host.puts("string")

Telnet#puts() adds "\n" to the last of "string".

WARNING: Telnet#print() NOT adds "\n" to the last of "string", in the future.

If "Telnetmode" option is true, then escape IAC code ("\xFF"). If
"Binmode" option is false, then convert "\n" to EOL(end of line) code.

If "WILL SGA" and "DO BIN", then EOL is CR. If "WILL SGA", then EOL is
CR + NULL. If the other cases, EOL is CR + LF.


=== TOGGLE TELNET COMMAND INTERPRETATION

  host.telnetmode          # return the current status (true or false)
  host.telnetmode = true   # do telnet command interpretation (default)
  host.telnetmode = false  # don't telnet command interpretation


=== TOGGLE NEWLINE TRANSLATION

  host.binmode          # return the current status (true or false)
  host.binmode = true   # no translate newline
  host.binmode = false  # translate newline (default)


=== LOGIN

  host.login("username", "password")
  host.login({"Name" => "username",
              "Password" => "password"})

if no password prompt:

  host.login("username")
  host.login({"Name" => "username"})


==== REALTIME OUTPUT

  host.login("username", "password"){|c| print c }
  host.login({"Name" => "username",
              "Password" => "password"}){|c| print c }

of cource, set sync=true or flush is necessary.



== EXAMPLE

=== LOGIN AND SEND COMMAND

  localhost = Net::Telnet::new({"Host" => "localhost",
                                "Timeout" => 10,
                                "Prompt" => /[$%#>] \z/n})
  localhost.login("username", "password"){|c| print c }
  localhost.cmd("command"){|c| print c }
  localhost.close


=== CHECKS A POP SERVER TO SEE IF YOU HAVE MAIL

  pop = Net::Telnet::new({"Host" => "your_destination_host_here",
                          "Port" => 110,
                          "Telnetmode" => false,
                          "Prompt" => /^\+OK/n})
  pop.cmd("user " + "your_username_here"){|c| print c}
  pop.cmd("pass " + "your_password_here"){|c| print c}
  pop.cmd("list"){|c| print c}


=end


require "socket"
require "delegate"
require "timeout"
require "English"

module Net
  class Telnet < SimpleDelegator

    IAC   = 255.chr # "\377" # "\xff" # interpret as command:
    DONT  = 254.chr # "\376" # "\xfe" # you are not to use option
    DO    = 253.chr # "\375" # "\xfd" # please, you use option
    WONT  = 252.chr # "\374" # "\xfc" # I won't use option
    WILL  = 251.chr # "\373" # "\xfb" # I will use option
    SB    = 250.chr # "\372" # "\xfa" # interpret as subnegotiation
    GA    = 249.chr # "\371" # "\xf9" # you may reverse the line
    EL    = 248.chr # "\370" # "\xf8" # erase the current line
    EC    = 247.chr # "\367" # "\xf7" # erase the current character
    AYT   = 246.chr # "\366" # "\xf6" # are you there
    AO    = 245.chr # "\365" # "\xf5" # abort output--but let prog finish
    IP    = 244.chr # "\364" # "\xf4" # interrupt process--permanently
    BREAK = 243.chr # "\363" # "\xf3" # break
    DM    = 242.chr # "\362" # "\xf2" # data mark--for connect. cleaning
    NOP   = 241.chr # "\361" # "\xf1" # nop
    SE    = 240.chr # "\360" # "\xf0" # end sub negotiation
    EOR   = 239.chr # "\357" # "\xef" # end of record (transparent mode)
    ABORT = 238.chr # "\356" # "\xee" # Abort process
    SUSP  = 237.chr # "\355" # "\xed" # Suspend process
    EOF   = 236.chr # "\354" # "\xec" # End of file
    SYNCH = 242.chr # "\362" # "\xf2" # for telfunc calls

    OPT_BINARY         =   0.chr # "\000" # "\x00" # Binary Transmission
    OPT_ECHO           =   1.chr # "\001" # "\x01" # Echo
    OPT_RCP            =   2.chr # "\002" # "\x02" # Reconnection
    OPT_SGA            =   3.chr # "\003" # "\x03" # Suppress Go Ahead
    OPT_NAMS           =   4.chr # "\004" # "\x04" # Approx Message Size Negotiation
    OPT_STATUS         =   5.chr # "\005" # "\x05" # Status
    OPT_TM             =   6.chr # "\006" # "\x06" # Timing Mark
    OPT_RCTE           =   7.chr # "\a"   # "\x07" # Remote Controlled Trans and Echo
    OPT_NAOL           =   8.chr # "\010" # "\x08" # Output Line Width
    OPT_NAOP           =   9.chr # "\t"   # "\x09" # Output Page Size
    OPT_NAOCRD         =  10.chr # "\n"   # "\x0a" # Output Carriage-Return Disposition
    OPT_NAOHTS         =  11.chr # "\v"   # "\x0b" # Output Horizontal Tab Stops
    OPT_NAOHTD         =  12.chr # "\f"   # "\x0c" # Output Horizontal Tab Disposition
    OPT_NAOFFD         =  13.chr # "\r"   # "\x0d" # Output Formfeed Disposition
    OPT_NAOVTS         =  14.chr # "\016" # "\x0e" # Output Vertical Tabstops
    OPT_NAOVTD         =  15.chr # "\017" # "\x0f" # Output Vertical Tab Disposition
    OPT_NAOLFD         =  16.chr # "\020" # "\x10" # Output Linefeed Disposition
    OPT_XASCII         =  17.chr # "\021" # "\x11" # Extended ASCII
    OPT_LOGOUT         =  18.chr # "\022" # "\x12" # Logout
    OPT_BM             =  19.chr # "\023" # "\x13" # Byte Macro
    OPT_DET            =  20.chr # "\024" # "\x14" # Data Entry Terminal
    OPT_SUPDUP         =  21.chr # "\025" # "\x15" # SUPDUP
    OPT_SUPDUPOUTPUT   =  22.chr # "\026" # "\x16" # SUPDUP Output
    OPT_SNDLOC         =  23.chr # "\027" # "\x17" # Send Location
    OPT_TTYPE          =  24.chr # "\030" # "\x18" # Terminal Type
    OPT_EOR            =  25.chr # "\031" # "\x19" # End of Record
    OPT_TUID           =  26.chr # "\032" # "\x1a" # TACACS User Identification
    OPT_OUTMRK         =  27.chr # "\e"   # "\x1b" # Output Marking
    OPT_TTYLOC         =  28.chr # "\034" # "\x1c" # Terminal Location Number
    OPT_3270REGIME     =  29.chr # "\035" # "\x1d" # Telnet 3270 Regime
    OPT_X3PAD          =  30.chr # "\036" # "\x1e" # X.3 PAD
    OPT_NAWS           =  31.chr # "\037" # "\x1f" # Negotiate About Window Size
    OPT_TSPEED         =  32.chr # " "    # "\x20" # Terminal Speed
    OPT_LFLOW          =  33.chr # "!"    # "\x21" # Remote Flow Control
    OPT_LINEMODE       =  34.chr # "\""   # "\x22" # Linemode
    OPT_XDISPLOC       =  35.chr # "#"    # "\x23" # X Display Location
    OPT_OLD_ENVIRON    =  36.chr # "$"    # "\x24" # Environment Option
    OPT_AUTHENTICATION =  37.chr # "%"    # "\x25" # Authentication Option
    OPT_ENCRYPT        =  38.chr # "&"    # "\x26" # Encryption Option
    OPT_NEW_ENVIRON    =  39.chr # "'"    # "\x27" # New Environment Option
    OPT_EXOPL          = 255.chr # "\377" # "\xff" # Extended-Options-List

    NULL = "\000"
    CR   = "\015"
    LF   = "\012"
    EOL  = CR + LF
    VERSION = "1.6.0"
    RELEASE_DATE = "2000-09-12"
    VERSION_CODE = 160
    RELEASE_CODE = 20000912

    def initialize(options)
      @options = options
      @options["Host"]       = "localhost"   unless @options.has_key?("Host")
      @options["Port"]       = 23            unless @options.has_key?("Port")
      @options["Prompt"]     = /[$%#>] \z/n  unless @options.has_key?("Prompt")
      @options["Timeout"]    = 10            unless @options.has_key?("Timeout")
      @options["Waittime"]   = 0             unless @options.has_key?("Waittime")
      unless @options.has_key?("Binmode")
        @options["Binmode"]    = false         
      else
        unless (true == @options["Binmode"] or false == @options["Binmode"])
          raise ArgumentError, "Binmode option required true or false"
        end
      end

      unless @options.has_key?("Telnetmode")
        @options["Telnetmode"] = true          
      else
        unless (true == @options["Telnetmode"] or false == @options["Telnetmode"])
          raise ArgumentError, "Telnetmode option required true or false"
        end
      end

      @telnet_option = { "SGA" => false, "BINARY" => false }

      if @options.has_key?("Output_log")
        @log = File.open(@options["Output_log"], 'a+')
        @log.sync = true
        @log.binmode
      end

      if @options.has_key?("Dump_log")
        @dumplog = File.open(@options["Dump_log"], 'a+')
        @dumplog.sync = true
        @dumplog.binmode
        def @dumplog.log_dump(dir, x)
          len = x.length
          addr = 0
          offset = 0
          while 0 < len
            if len < 16
              line = x[offset, len]
            else
              line = x[offset, 16]
            end
            hexvals = line.unpack('H*')[0]
            hexvals.concat ' ' * (32 - hexvals.length)
            hexvals = format "%s %s %s %s  " * 4, *hexvals.unpack('a2' * 16)
            line = line.gsub(/[\000-\037\177-\377]/n, '.')
            printf "%s 0x%5.5x: %s%s\n", dir, addr, hexvals, line
            addr += 16
            offset += 16
            len -= 16
          end
          print "\n"
        end
      end

      if @options.has_key?("Proxy")
        if @options["Proxy"].kind_of?(Net::Telnet)
          @sock = @options["Proxy"].sock
        elsif @options["Proxy"].kind_of?(IO)
          @sock = @options["Proxy"]
        else
          raise "Error; Proxy is Net::Telnet or IO object."
        end
      else
        message = "Trying " + @options["Host"] + "...\n"
        yield(message) if iterator?
        @log.write(message) if @options.has_key?("Output_log")
        @dumplog.log_dump('#', message) if @options.has_key?("Dump_log")

        begin
          if @options["Timeout"] == false
            @sock = TCPsocket.open(@options["Host"], @options["Port"])
          else
            timeout(@options["Timeout"]) do
              @sock = TCPsocket.open(@options["Host"], @options["Port"])
            end
          end
        rescue TimeoutError
          raise TimeoutError, "timed-out; opening of the host"
        rescue
          @log.write($ERROR_INFO.to_s + "\n") if @options.has_key?("Output_log")
          @dumplog.log_dump('#', $ERROR_INFO.to_s + "\n") if @options.has_key?("Dump_log")
          raise
        end
        @sock.sync = true
        @sock.binmode

        message = "Connected to " + @options["Host"] + ".\n"
        yield(message) if iterator?
        @log.write(message) if @options.has_key?("Output_log")
        @dumplog.log_dump('#', message) if @options.has_key?("Dump_log")
      end

      super(@sock)
    end # initialize

    attr :sock

    def telnetmode(mode = nil)
      if mode
        if (true == mode or false == mode)
          @options["Telnetmode"] = mode
        else
          raise ArgumentError, "required true or false"
        end
      else
        @options["Telnetmode"]
      end
    end

    def telnetmode=(mode)
      if (true == mode or false == mode)
        @options["Telnetmode"] = mode
      else
        raise ArgumentError, "required true or false"
      end
    end

    def binmode(mode = nil)
      if mode
        if (true == mode or false == mode)
          @options["Binmode"] = mode
        else
          raise ArgumentError, "required true or false"
        end
      else
        @options["Binmode"] 
      end
    end

    def binmode=(mode)
      if (true == mode or false == mode)
        @options["Binmode"] = mode
      else
        raise ArgumentError, "required true or false"
      end
    end

    def preprocess(string)
      # combine CR+NULL into CR
      string = string.gsub(/#{CR}#{NULL}/no, CR) if @options["Telnetmode"]

      # combine EOL into "\n"
      string = string.gsub(/#{EOL}/no, "\n") unless @options["Binmode"]

      string.gsub(/#{IAC}(
                   [#{IAC}#{AO}#{AYT}#{DM}#{IP}#{NOP}]|
                   [#{DO}#{DONT}#{WILL}#{WONT}]
                     [#{OPT_BINARY}-#{OPT_NEW_ENVIRON}#{OPT_EXOPL}]|
                   #{SB}[^#{IAC}]*#{IAC}#{SE}
                 )/xno) do
        if    IAC == $1         # handle escaped IAC characters
          IAC
        elsif AYT == $1         # respond to "IAC AYT" (are you there)
          self.write("nobody here but us pigeons" + EOL)
          ''
        elsif DO[0] == $1[0]    # respond to "IAC DO x"
          if OPT_BINARY[0] == $1[1]
            @telnet_option["BINARY"] = true
            self.write(IAC + WILL + OPT_BINARY)
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
        else
          ''
        end
      end
    end # preprocess

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
      rest = ''
      until(prompt === line and not IO::select([@sock], nil, nil, waittime))
        unless IO::select([@sock], nil, nil, time_out)
          raise TimeoutError, "timed-out; wait for the next data"
        end
        begin
          c = @sock.sysread(1024 * 1024)
          @dumplog.log_dump('<', c) if @options.has_key?("Dump_log")
          if @options["Telnetmode"]
            if Integer(c.rindex(/#{IAC}#{SE}/no)) <
               Integer(c.rindex(/#{IAC}#{SB}/no))
              buf = preprocess(rest + c[0 ... c.rindex(/#{IAC}#{SB}/no)])
              rest = c[c.rindex(/#{IAC}#{SB}/no) .. -1]
            elsif pt = c.rindex(/#{IAC}[^#{IAC}#{AO}#{AYT}#{DM}#{IP}#{NOP}]?\z/no)
              buf = preprocess(rest + c[0 ... pt])
              rest = c[pt .. -1]
            else
              buf = preprocess(c)
              rest = ''
            end
          end
          @log.print(buf) if @options.has_key?("Output_log")
          line.concat(buf)
          yield buf if iterator?
        rescue EOFError # End of file reached
          if line == ''
            line = nil
            yield nil if iterator?
          end
          break
        end
      end
      line
    end

    def write(string)
      length = string.length
      while 0 < length
        IO::select(nil, [@sock])
        @dumplog.log_dump('>', string[-length..-1]) if @options.has_key?("Dump_log")
        length -= @sock.syswrite(string[-length..-1])
      end
    end

    def print(string)
      if $VERBOSE
        $stderr.puts 'WARNING: Telnet#print("string") NOT adds "\n" to the last of "string", in the future.'
        $stderr.puts '         cf. Telnet#puts().'
      end
      string = string + "\n"
      string = string.gsub(/#{IAC}/no, IAC + IAC) if @options["Telnetmode"]

      if @options["Binmode"]
        self.write(string)
      else
        if @telnet_option["BINARY"] and @telnet_option["SGA"]
          # IAC WILL SGA IAC DO BIN send EOL --> CR
          self.write(string.gsub(/\n/n, CR))
        elsif @telnet_option["SGA"]
          # IAC WILL SGA send EOL --> CR+NULL
          self.write(string.gsub(/\n/n, CR + NULL))
        else
          # NONE send EOL --> CR+LF
          self.write(string.gsub(/\n/n, EOL))
        end
      end
    end

    def puts(string)
      self.print(string)
    end

    def cmd(options)
      match    = @options["Prompt"]
      time_out = @options["Timeout"]

      if options.kind_of?(Hash)
        string   = options["String"]
        match    = options["Match"]   if options.has_key?("Match")
        time_out = options["Timeout"] if options.has_key?("Timeout")
      else
        string = options
      end

      self.print(string)
      if iterator?
        waitfor({"Prompt" => match, "Timeout" => time_out}){|c| yield c }
      else
        waitfor({"Prompt" => match, "Timeout" => time_out})
      end
    end

    def login(options, password = nil)
      if options.kind_of?(Hash)
        username = options["Name"]
        password = options["Password"]
      else
        username = options
      end

      if iterator?
        line = waitfor(/login[: ]*\z/n){|c| yield c }
        if password
          line.concat( cmd({"String" => username,
                            "Match" => /Password[: ]*\z/n}){|c| yield c } )
          line.concat( cmd(password){|c| yield c } )
        else
          line.concat( cmd(username){|c| yield c } )
        end
      else
        line = waitfor(/login[: ]*\z/n)
        if password
          line.concat( cmd({"String" => username,
                            "Match" => /Password[: ]*\z/n}) )
          line.concat( cmd(password) )
        else
          line.concat( cmd(username) )
        end
      end
      line
    end

  end
end


=begin

== HISTORY

* Tue Sep 12 06:52:48 JST 2000 - wakou
  * version 1.6.0
  * correct: document.
    thanks to Kazuhiro NISHIYAMA <zn@mbf.nifty.com>
  * add: Telnet#puts().

* Sun Jun 18 23:31:44 JST 2000 - wakou
  * version 1.5.0
  * change: version syntax. old: x.yz, now: x.y.z

* 2000/05/24 06:57:38 - wakou
  * version 1.40
  * improve: binmode(), telnetmode() interface.
    thanks to Dave Thomas <Dave@thomases.com>

* 2000/05/09 22:02:56 - wakou
  * version 1.32
  * require English.rb

* 2000/05/02 21:48:39 - wakou
  * version 1.31
  * Proxy option: can receive IO object.

* 2000/04/03 18:27:02 - wakou
  * version 1.30
  * telnet.rb --> net/telnet.rb

* 2000/01/24 17:02:57 - wakou
  * version 1.20
  * respond to "IAC WILL x" with "IAC DONT x"
  * respond to "IAC WONT x" with "IAC DONT x"
  * better dumplog format.
    thanks to WATANABE Hirofumi <Hirofumi.Watanabe@jp.sony.com>

* 2000/01/18 17:47:31 - wakou
  * version 1.10
  * bug fix: write method
  * respond to "IAC WILL BINARY" with "IAC DO BINARY"

* 1999/10/04 22:51:26 - wakou
  * version 1.00
  * bug fix: waitfor(preprocess) method.
    thanks to Shin-ichiro Hara <sinara@blade.nagaokaut.ac.jp>
  * add simple support for AO, DM, IP, NOP, SB, SE
  * COUTION! TimeOut --> TimeoutError

* 1999/09/21 21:24:07 - wakou
  * version 0.50
  * add write method

* 1999/09/17 17:41:41 - wakou
  * version 0.40
  * bug fix: preprocess method

* 1999/09/14 23:09:05 - wakou
  * version 0.30
  * change prompt check order.
      not IO::select([@sock], nil, nil, waittime) and prompt === line
      --> prompt === line and not IO::select([@sock], nil, nil, waittime)

* 1999/09/13 22:28:33 - wakou
  * version 0.24
  * Telnet#login: if ommit password, then not require password prompt.

* 1999/08/10 05:20:21 - wakou
  * version 0.232
  * STATUS OUTPUT sample code typo.
    thanks to Tadayoshi Funaba <tadf@kt.rim.or.jp>
      host = Telnet.new({"Hosh" => "localhost"){|c| print c }
      --> host = Telnet.new({"Host" => "localhost"){|c| print c }

* 1999/07/16 13:39:42 - wakou
  * version 0.231
  * TRUE --> true, FALSE --> false

* 1999/07/15 22:32:09 - wakou
  * version 0.23
  * waitfor: if end of file reached, then return nil.

* 1999/06/29 09:08:51 - wakou
  * version 0.22
  * new, waitfor, cmd: {"Timeout" => false}  # ignore timeout

* 1999/06/28 18:18:55 - wakou
  * version 0.21
  * waitfor: not rescue (EOFError)

* 1999/06/04 06:24:58 - wakou
  * version 0.20
  * waitfor: support for divided telnet command

* 1999/05/22 - wakou
  * version 0.181
  * bug fix: print method

* 1999/05/14 - wakou
  * version 0.18
  * respond to "IAC WON'T SGA" with "IAC DON'T SGA"
  * DON'T SGA : end of line --> CR + LF
  * bug fix: preprocess method

* 1999/04/30 - wakou
  * version 0.17
  * bug fix: $! + "\n"  -->  $!.to_s + "\n"

* 1999/04/11 - wakou
  * version 0.163
  * STDOUT.write(message) --> yield(message) if iterator?

* 1999/03/17 - wakou
  * version 0.162
  * add "Proxy" option
  * required timeout.rb

* 1999/02/03 - wakou
  * version 0.161
  * select --> IO::select

* 1998/10/09 - wakou
  * version 0.16
  * preprocess method change for the better
  * add binmode method.
  * change default Binmode. TRUE --> FALSE

* 1998/10/04 - wakou
  * version 0.15
  * add telnetmode method.

* 1998/09/22 - wakou
  * version 0.141
  * change default prompt. /[$%#>] $/ --> /[$%#>] \Z/

* 1998/09/01 - wakou
  * version 0.14
  * IAC WILL SGA             send EOL --> CR+NULL
  * IAC WILL SGA IAC DO BIN  send EOL --> CR
  * NONE                     send EOL --> LF
  * add Dump_log option.

* 1998/08/25 - wakou
  * version 0.13
  * add print method.

* 1998/08/05 - wakou
  * version 0.122
  * support for HP-UX 10.20.
    thanks to WATANABE Tetsuya <tetsu@jpn.hp.com>
  * socket.<< --> socket.write

* 1998/07/15 - wakou
  * version 0.121
  * string.+= --> string.concat

* 1998/06/01 - wakou
  * version 0.12
  * add timeout, waittime.

* 1998/04/21 - wakou
  * version 0.11
  * add realtime output.

* 1998/04/13 - wakou
  * version 0.10
  * first release.

$Date$
=end
