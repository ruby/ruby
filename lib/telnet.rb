=begin
$Date: 1999/06/04 06:24:58 $

== SIMPLE TELNET CLIANT LIBRARY

telnet.rb

Version 0.20

Wakou Aoyama <wakou@fsinet.or.jp>


=== MAKE NEW TELNET OBJECT

	host = Telnet.new({"Binmode" => FALSE,           # default: FALSE
	                   "Host" => "localhost",        # default: "localhost"
	                   "Output_log" => "output_log", # default: not output
	                   "Dump_log" => "dump_log",     # default: not output
	                   "Port" => 23,                 # default: 23
	                   "Prompt" => /[$%#>] \z/n,     # default: /[$%#>] \z/n
	                   "Telnetmode" => TRUE,         # default: TRUE
	                   "Timeout" => 10,              # default: 10
	                   "Waittime" => 0,              # default: 0
	                   "Proxy" => proxy})            # default: nil
                                    # proxy is Telnet or TCPsocket object

Telnet object has socket class methods.

if set "Telnetmode" option FALSE. not TELNET command interpretation.
"Waittime" is time to confirm "Prompt". There is a possibility that
the same character as "Prompt" is included in the data, and, when
the network or the host is very heavy, the value is enlarged.

=== STATUS OUTPUT

	host = Telnet.new({"Hosh" => "localhost"){|c| print c }

connection status output.

example

	Trying localhost...
	Connected to localhost.


=== WAIT FOR MATCH

	line = host.waitfor(/match/)
	line = host.waitfor({"Match"   => /match/,
	                     "String"  => "string",
	                     "Timeout" => secs})

if set "String" option. Match = Regexp.new(quote(string))


==== REALTIME OUTPUT

	host.waitfor(/match/){|c| print c }
	host.waitfor({"Match"   => /match/,
	              "String"  => "string",
	              "Timeout" => secs}){|c| print c}

of cource, set sync=TRUE or flush is necessary.


=== SEND STRING AND WAIT PROMPT

	line = host.cmd("string")
	line = host.cmd({"String" => "string",
	                 "Prompt" => /[$%#>] \z/n,
	                 "Timeout" => 10})


==== REALTIME OUTPUT

	host.cmd("string"){|c| print c }
	host.cmd({"String" => "string",
	          "Prompt" => /[$%#>] \z/n,
	          "Timeout" => 10}){|c| print c }

of cource, set sync=TRUE or flush is necessary.


=== SEND STRING

	host.print("string")


=== TURN TELNET COMMAND INTERPRETATION

	host.telnetmode        # turn on/off
	host.telnetmode(TRUE)  # on
	host.telnetmode(FALSE) # off


=== TOGGLE NEWLINE TRANSLATION

	host.binmode        # turn TRUE/FALSE
	host.binmode(TRUE)  # no translate newline
	host.binmode(FALSE) # translate newline


=== LOGIN

	host.login("username", "password")
	host.login({"Name" => "username",
	            "Password" => "password",
	            "Prompt" => /[$%#>] \z/n,
	            "Timeout" => 10})


==== REALTIME OUTPUT

	host.login("username", "password"){|c| print c }
	host.login({"Name" => "username",
	            "Password" => "password",
	            "Prompt" => /[$%#>] \z/n,
	            "Timeout" => 10}){|c| print c }

of cource, set sync=TRUE or flush is necessary.


== EXAMPLE

=== LOGIN AND SEND COMMAND

	localhost = Telnet.new({"Host" => "localhost",
	                        "Timeout" => 10,
	                        "Prompt" => /[$%#>] \z/n})
	localhost.login("username", "password"){|c| print c }
	localhost.cmd("command"){|c| print c }
	localhost.close


=== CHECKS A POP SERVER TO SEE IF YOU HAVE MAIL

	pop = Telnet.new({"Host" => "your_destination_host_here",
	                  "Port" => 110,
	                  "Telnetmode" => FALSE,
	                  "Prompt" => /^\+OK/n})
	pop.cmd("user " + "your_username_here"){|c| print c}
	pop.cmd("pass " + "your_password_here"){|c| print c}
	pop.cmd("list"){|c| print c}


== HISTORY

=== Version 0.20
waitfor: support for divided telnet command

=== Version 0.181 1999/05/22
bug fix: print method

=== Version 0.18 1999/05/14
respond to "IAC WON'T SGA" with "IAC DON'T SGA"

DON'T SGA : end of line --> CR + LF

bug fix: preprocess method

=== Version 0.17 1999/04/30
bug fix: $! + "\n"  -->  $!.to_s + "\n"

=== Version 0.163 1999/04/11
STDOUT.write(message) --> yield(message) if iterator?

=== Version 0.162 1999/03/17
add "Proxy" option

required timeout.rb

=== Version 0.161 1999/02/03
select --> IO::select

=== Version 0.16 1998/10/09
preprocess method change for the better

add binmode method.

change default Binmode 
TRUE --> FALSE

=== Version 0.15 1998/10/04
add telnetmode method.

=== Version 0.141 1998/09/22
change default prompt
	/[$%#>] $/ --> /[$%#>] \Z/

=== Version 0.14 1998/09/01
IAC WILL SGA             send EOL --> CR+NULL

IAC WILL SGA IAC DO BIN  send EOL --> CR

NONE                     send EOL --> LF

add Dump_log option.

=== Version 0.13 1998/08/25
add print method.

=== Version 0.122 1998/08/05
support for HP-UX 10.20    thanks to WATANABE Tetsuya <tetsu@jpn.hp.com>

socket.<< --> socket.write

=== Version 0.121 1998/07/15
string.+= --> string.concat

=== Version 0.12 1998/06/01
add timeout, waittime.

=== Version 0.11 1998/04/21
add realtime output.

=== Version 0.10 1998/04/13
first release.

=end

require "socket"
require "delegate"
require "thread"
require "timeout"
TimeOut = TimeoutError

class Telnet < SimpleDelegator

  IAC   = 255.chr # "\377" # interpret as command:
  DONT  = 254.chr # "\376" # you are not to use option
  DO    = 253.chr # "\375" # please, you use option
  WONT  = 252.chr # "\374" # I won't use option
  WILL  = 251.chr # "\373" # I will use option
  SB    = 250.chr # "\372" # interpret as subnegotiation
  GA    = 249.chr # "\371" # you may reverse the line
  EL    = 248.chr # "\370" # erase the current line
  EC    = 247.chr # "\367" # erase the current character
  AYT   = 246.chr # "\366" # are you there
  AO    = 245.chr # "\365" # abort output--but let prog finish
  IP    = 244.chr # "\364" # interrupt process--permanently
  BREAK = 243.chr # "\363" # break
  DM    = 242.chr # "\362" # data mark--for connect. cleaning
  NOP   = 241.chr # "\361" # nop
  SE    = 240.chr # "\360" # end sub negotiation
  EOR   = 239.chr # "\357" # end of record (transparent mode)
  ABORT = 238.chr # "\356" # Abort process
  SUSP  = 237.chr # "\355" # Suspend process
  EOF   = 236.chr # "\354" # End of file
  SYNCH = 242.chr # "\362" # for telfunc calls

  OPT_BINARY         =   0.chr # "\000" # Binary Transmission
  OPT_ECHO           =   1.chr # "\001" # Echo
  OPT_RCP            =   2.chr # "\002" # Reconnection
  OPT_SGA            =   3.chr # "\003" # Suppress Go Ahead
  OPT_NAMS           =   4.chr # "\004" # Approx Message Size Negotiation
  OPT_STATUS         =   5.chr # "\005" # Status
  OPT_TM             =   6.chr # "\006" # Timing Mark
  OPT_RCTE           =   7.chr # "\a"   # Remote Controlled Trans and Echo
  OPT_NAOL           =   8.chr # "\010" # Output Line Width
  OPT_NAOP           =   9.chr # "\t"   # Output Page Size
  OPT_NAOCRD         =  10.chr # "\n"   # Output Carriage-Return Disposition
  OPT_NAOHTS         =  11.chr # "\v"   # Output Horizontal Tab Stops
  OPT_NAOHTD         =  12.chr # "\f"   # Output Horizontal Tab Disposition
  OPT_NAOFFD         =  13.chr # "\r"   # Output Formfeed Disposition
  OPT_NAOVTS         =  14.chr # "\016" # Output Vertical Tabstops
  OPT_NAOVTD         =  15.chr # "\017" # Output Vertical Tab Disposition
  OPT_NAOLFD         =  16.chr # "\020" # Output Linefeed Disposition
  OPT_XASCII         =  17.chr # "\021" # Extended ASCII
  OPT_LOGOUT         =  18.chr # "\022" # Logout
  OPT_BM             =  19.chr # "\023" # Byte Macro
  OPT_DET            =  20.chr # "\024" # Data Entry Terminal
  OPT_SUPDUP         =  21.chr # "\025" # SUPDUP
  OPT_SUPDUPOUTPUT   =  22.chr # "\026" # SUPDUP Output
  OPT_SNDLOC         =  23.chr # "\027" # Send Location
  OPT_TTYPE          =  24.chr # "\030" # Terminal Type
  OPT_EOR            =  25.chr # "\031" # End of Record
  OPT_TUID           =  26.chr # "\032" # TACACS User Identification
  OPT_OUTMRK         =  27.chr # "\e"   # Output Marking
  OPT_TTYLOC         =  28.chr # "\034" # Terminal Location Number
  OPT_3270REGIME     =  29.chr # "\035" # Telnet 3270 Regime
  OPT_X3PAD          =  30.chr # "\036" # X.3 PAD
  OPT_NAWS           =  31.chr # "\037" # Negotiate About Window Size
  OPT_TSPEED         =  32.chr # " "    # Terminal Speed
  OPT_LFLOW          =  33.chr # "!"    # Remote Flow Control
  OPT_LINEMODE       =  34.chr # "\""   # Linemode
  OPT_XDISPLOC       =  35.chr # "#"    # X Display Location
  OPT_OLD_ENVIRON    =  36.chr # "$"    # Environment Option
  OPT_AUTHENTICATION =  37.chr # "%"    # Authentication Option
  OPT_ENCRYPT        =  38.chr # "&"    # Encryption Option
  OPT_NEW_ENVIRON    =  39.chr # "'"    # New Environment Option
  OPT_EXOPL          = 255.chr # "\377" # Extended-Options-List

  NULL = "\000"
  CR   = "\015"
  LF   = "\012"
  EOL  = CR + LF
v = $-v
$-v = false
  VERSION = "0.20"
  RELEASE_DATE = "$Date: 1999/06/04 06:24:58 $"
$-v = v

  def initialize(options)
    @options = options
    @options["Binmode"]    = FALSE         if not @options.include?("Binmode")
    @options["Host"]       = "localhost"   if not @options.include?("Host")
    @options["Port"]       = 23            if not @options.include?("Port")
    @options["Prompt"]     = /[$%#>] \z/n  if not @options.include?("Prompt")
    @options["Telnetmode"] = TRUE          if not @options.include?("Telnetmode")
    @options["Timeout"]    = 10            if not @options.include?("Timeout")
    @options["Waittime"]   = 0             if not @options.include?("Waittime")

    @telnet_option = { "SGA" => FALSE, "BINARY" => FALSE }

    if @options.include?("Output_log")
      @log = File.open(@options["Output_log"], 'a+')
      @log.sync = TRUE
      @log.binmode
    end

    if @options.include?("Dump_log")
      @dumplog = File.open(@options["Dump_log"], 'a+')
      @dumplog.sync = TRUE
      @dumplog.binmode
    end

    if @options.include?("Proxy")
      if @options["Proxy"].kind_of?(Telnet)
        @sock = @options["Proxy"].sock
      elsif @options["Proxy"].kind_of?(TCPsocket)
        @sock = @options["Proxy"]
      else
        raise "Error; Proxy is Telnet or TCPSocket object."
      end
    else
      message = "Trying " + @options["Host"] + "...\n"
      yield(message) if iterator?
      @log.write(message) if @options.include?("Output_log")
      @dumplog.write(message) if @options.include?("Dump_log")

      begin
        timeout(@options["Timeout"]){
          @sock = TCPsocket.open(@options["Host"], @options["Port"])
        }
      rescue TimeoutError
        raise TimeOut, "timed-out; opening of the host"
      rescue
        @log.write($!.to_s + "\n") if @options.include?("Output_log")
        @dumplog.write($!.to_s + "\n") if @options.include?("Dump_log")
        raise
      end
      @sock.sync = TRUE
      @sock.binmode

      message = "Connected to " + @options["Host"] + ".\n"
      yield(message) if iterator?
      @log.write(message) if @options.include?("Output_log")
      @dumplog.write(message) if @options.include?("Dump_log")
    end

    super(@sock)
  end # initialize

  attr :sock

  def telnetmode(mode = 'turn')
    if 'turn' == mode
      @options["Telnetmode"] = @options["Telnetmode"] ? FALSE : TRUE
    else
      @options["Telnetmode"] = mode ? TRUE : FALSE
    end
  end

  def binmode(mode = 'turn')
    if 'turn' == mode
      @options["Binmode"] = @options["Binmode"] ? FALSE : TRUE
    else
      @options["Binmode"] = mode ? TRUE : FALSE
    end
  end

  def preprocess(string)
    str = string.dup

    # combine CR+NULL into CR
    str.gsub!(/#{CR}#{NULL}/no, CR) if @options["Telnetmode"]

    # combine EOL into "\n"
    str.gsub!(/#{EOL}/no, "\n") if not @options["Binmode"]

    # respond to "IAC DO x"
    str.gsub!(/([^#{IAC}]?)#{IAC}#{DO}([#{OPT_BINARY}-#{OPT_NEW_ENVIRON}#{OPT_EXOPL}])/no){
      if OPT_BINARY == $2
        @telnet_option["BINARY"] = TRUE
        @sock.write(IAC + WILL + OPT_BINARY)
      else
        @sock.write(IAC + WONT + $2)
      end
      $1
    }

    # respond to "IAC DON'T x" with "IAC WON'T x"
    str.gsub!(/([^#{IAC}]?)#{IAC}#{DONT}([#{OPT_BINARY}-#{OPT_NEW_ENVIRON}#{OPT_EXOPL}])/no){
      @sock.write(IAC + WONT + $2)
      $1
    }

    # respond to "IAC WILL x"
    str.gsub!(/([^#{IAC}]?)#{IAC}#{WILL}([#{OPT_BINARY}-#{OPT_NEW_ENVIRON}#{OPT_EXOPL}])/no){
      if OPT_ECHO == $2
        @sock.write(IAC + DO + OPT_ECHO)
      elsif OPT_SGA == $2
        @telnet_option["SGA"] = TRUE
        @sock.write(IAC + DO + OPT_SGA)
      end
      $1
    }

    # respond to "IAC WON'T x"
    str.gsub!(/([^#{IAC}]?)#{IAC}#{WONT}([#{OPT_BINARY}-#{OPT_NEW_ENVIRON}#{OPT_EXOPL}])/no){
      if OPT_ECHO == $2
        @sock.write(IAC + DONT + OPT_ECHO)
      elsif OPT_SGA == $2
        @telnet_option["SGA"] = FALSE
        @sock.write(IAC + DONT + OPT_SGA)
      end
      $1
    }

    # respond to "IAC AYT" (are you there)
    str.gsub!(/([^#{IAC}]?)#{IAC}#{AYT}/no){
      @sock.write("nobody here but us pigeons" + EOL)
      $1
    }

    str.gsub!(/#{IAC}#{IAC}/no, IAC) # handle escaped IAC characters

    str
  end # preprocess

  def waitfor(options)
    time_out = @options["Timeout"]
    waittime = @options["Waittime"]

    if options.kind_of?(Hash)
      prompt   = if options.include?("Match")
                   options["Match"]   
                 elsif options.include?("Prompt")
                   options["Prompt"]
                 elsif options.include?("String")
                   Regexp.new( Regexp.quote(options["String"]) )
                 end
      time_out = options["Timeout"]  if options.include?("Timeout")
      waittime = options["Waittime"] if options.include?("Waittime")
    else
      prompt = options
    end

    line = ''
    buf = ''
    until(not IO::select([@sock], nil, nil, waittime) and prompt === line)
      raise TimeOut, "timed-out; wait for the next data" if
        not IO::select([@sock], nil, nil, time_out)
      begin
        c = @sock.sysread(1024 * 1024)
        @dumplog.print(c) if @options.include?("Dump_log")
        buf.concat c
        if @options["Telnetmode"]
          buf = preprocess(buf) 
          if /#{IAC}.?\z/no === buf
            next
          end 
        end 
        @log.print(buf) if @options.include?("Output_log")
        yield buf if iterator?
        line.concat(buf)
        buf = ''
      rescue EOFError # End of file reached
        break
      end
    end
    line
  end

  def print(string)
    str = string.dup + "\n"

    str.gsub!(/#{IAC}/no, IAC + IAC) if @options["Telnetmode"]

    if not @options["Binmode"]
      if @telnet_option["BINARY"] and @telnet_option["SGA"]
        # IAC WILL SGA IAC DO BIN send EOL --> CR
        str.gsub!(/\n/n, CR)
      elsif @telnet_option["SGA"]
        # IAC WILL SGA send EOL --> CR+NULL
        str.gsub!(/\n/n, CR + NULL)
      else
        # NONE send EOL --> CR+LF
        str.gsub!(/\n/n, EOL)
      end
    end

    @sock.write(str)
  end

  def cmd(options)
    match    = @options["Prompt"]
    time_out = @options["Timeout"]

    if options.kind_of?(Hash)
      string   = options["String"]
      match    = options["Match"]   if options.include?("Match")
      time_out = options["Timeout"] if options.include?("Timeout")
    else
      string = options
    end

    IO::select(nil, [@sock])
    print(string)
    if iterator?
      waitfor({"Prompt" => match, "Timeout" => time_out}){|c| yield c }
    else
      waitfor({"Prompt" => match, "Timeout" => time_out})
    end
  end

  def login(options, password = '')
    if options.kind_of?(Hash)
      username = options["Name"]
      password = options["Password"]
    else
      username = options
    end

    if iterator?
      line = waitfor(/login[: ]*\z/n){|c| yield c }
      line.concat( cmd({"String" => username,
                        "Match" => /Password[: ]*\z/n}){|c| yield c } )
      line.concat( cmd(password){|c| yield c } )
    else
      line = waitfor(/login[: ]*\z/n)
      line.concat( cmd({"String" => username,
                        "Match" => /Password[: ]*\z/n}) )
      line.concat( cmd(password) )
    end
    line
  end

end
