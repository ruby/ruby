=begin

telnet.rb ver0.161 1999/02/03
Wakou Aoyama <wakou@fsinet.or.jp>

ver0.161 1999/02/03
select --> IO::select

ver0.16 1998/10/09
preprocess method change for the better
add binmode method.
change default Binmode
TRUE --> FALSE

ver0.15 1998/10/04
add telnetmode method.

ver0.141 1998/09/22
change default prompt
/[$%#>] $/ --> /[$%#>] \Z/

ver0.14 1998/09/01
IAC WILL SGA             send EOL --> CR+NULL
IAC WILL SGA IAC DO BIN  send EOL --> CR
NONE                     send EOL --> LF
add Dump_log option.

ver0.13 1998/08/25
add print method.

ver0.122 1998/08/05
support for HP-UX 10.20    thanks to WATANABE Tetsuya <tetsu@jpn.hp.com>
socket.<< --> socket.write

ver0.121 1998/07/15
string.+= --> string.concat

ver0.12 1998/06/01
add timeout, waittime.

ver0.11 1998/04/21
add realtime output.

ver0.10 1998/04/13
first release.

== make new Telnet object
host = Telnet.new({"Binmode" => FALSE,             default: FALSE
                   "Host" => "localhost",          default: "localhost"
                   "Output_log" => "output_log",   default: not output
                   "Dump_log" => "dump_log",       default: not output
                   "Port" => 23,                   default: 23
                   "Prompt" => /[$%#>] \Z/,        default: /[$%#>] \Z/
                   "Telnetmode" => TRUE,           default: TRUE
                   "Timeout" => 10,                default: 10
                   "Waittime" => 0})               default: 0

if set "Telnetmode" option FALSE. not TELNET command interpretation.
"Waittime" is time to confirm "Prompt". There is a possibility that
the same character as "Prompt" is included in the data, and, when
the network or the host is very heavy, the value is enlarged.

== wait for match
line = host.waitfor(/match/)
line = host.waitfor({"Match"   => /match/,
                     "String"  => "string",
                     "Timeout" => secs})
if set "String" option. Match = Regexp.new(quote(string))

realtime output. of cource, set sync=TRUE or flush is necessary.
host.waitfor(/match/){|c| print c }
host.waitfor({"Match"   => /match/,
              "String"  => "string",
              "Timeout" => secs}){|c| print c}

== send string and wait prompt
line = host.cmd("string")
line = host.cmd({"String" => "string",
                 "Prompt" => /[$%#>] \Z/,
                 "Timeout" => 10})

realtime output. of cource, set sync=TRUE or flush is necessary.
host.cmd("string"){|c| print c }
host.cmd({"String" => "string",
          "Prompt" => /[$%#>] \Z/,
          "Timeout" => 10}){|c| print c }

== send string
host.print("string")

== turn telnet command interpretation
host.telnetmode        # turn on/off
host.telnetmode(TRUE)  # on
host.telnetmode(FALSE) # off

== toggle newline translation
host.binmode        # turn TRUE/FALSE
host.binmode(TRUE)  # no translate newline
host.binmode(FALSE) # translate newline

== login
host.login("username", "password")
host.login({"Name" => "username",
            "Password" => "password",
            "Prompt" => /[$%#>] \Z/,
            "Timeout" => 10})

realtime output. of cource, set sync=TRUE or flush is necessary.
host.login("username", "password"){|c| print c }
host.login({"Name" => "username",
            "Password" => "password",
            "Prompt" => /[$%#>] \Z/,
            "Timeout" => 10}){|c| print c }

and Telnet object has socket class methods

== sample
localhost = Telnet.new({"Host" => "localhost",
                        "Timeout" => 10,
                        "Prompt" => /[$%#>] \Z/})
localhost.login("username", "password"){|c| print c }
localhost.cmd("command"){|c| print c }
localhost.close

== sample 2
checks a POP server to see if you have mail.

pop = Telnet.new({"Host" => "your_destination_host_here",
                  "Port" => 110,
                  "Telnetmode" => FALSE,
                  "Prompt" => /^\+OK/})
pop.cmd("user " + "your_username_here"){|c| print c}
pop.cmd("pass " + "your_password_here"){|c| print c}
pop.cmd("list"){|c| print c}

=end

require "socket"
require "delegate"
require "thread"

class TimeOut < Exception
end

class Telnet < SimpleDelegator

  def timeout(sec)
    is_timeout = FALSE 
    begin
      x = Thread.current
      y = Thread.start {
        sleep sec
        if x.alive?
          #print "timeout!\n"
          x.raise TimeOut, "timeout"
        end
      }
      begin
        yield
      rescue TimeOut
        is_timeout = TRUE
      end
    ensure
      Thread.kill y if y && y.alive?
    end
    is_timeout
  end

  IAC   = 255.chr  # interpret as command:
  DONT  = 254.chr  # you are not to use option
  DO    = 253.chr  # please, you use option
  WONT  = 252.chr  # I won't use option
  WILL  = 251.chr  # I will use option
  SB    = 250.chr  # interpret as subnegotiation
  GA    = 249.chr  # you may reverse the line
  EL    = 248.chr  # erase the current line
  EC    = 247.chr  # erase the current character
  AYT   = 246.chr  # are you there
  AO    = 245.chr  # abort output--but let prog finish
  IP    = 244.chr  # interrupt process--permanently
  BREAK = 243.chr  # break
  DM    = 242.chr  # data mark--for connect. cleaning
  NOP   = 241.chr  # nop
  SE    = 240.chr  # end sub negotiation
  EOR   = 239.chr  # end of record (transparent mode)
  ABORT = 238.chr  # Abort process
  SUSP  = 237.chr  # Suspend process
  EOF   = 236.chr  # End of file
  SYNCH = 242.chr  # for telfunc calls

  OPT_BINARY         =   0.chr  # Binary Transmission
  OPT_ECHO           =   1.chr  # Echo
  OPT_RCP            =   2.chr  # Reconnection
  OPT_SGA            =   3.chr  # Suppress Go Ahead
  OPT_NAMS           =   4.chr  # Approx Message Size Negotiation
  OPT_STATUS         =   5.chr  # Status
  OPT_TM             =   6.chr  # Timing Mark
  OPT_RCTE           =   7.chr  # Remote Controlled Trans and Echo
  OPT_NAOL           =   8.chr  # Output Line Width
  OPT_NAOP           =   9.chr  # Output Page Size
  OPT_NAOCRD         =  10.chr  # Output Carriage-Return Disposition
  OPT_NAOHTS         =  11.chr  # Output Horizontal Tab Stops
  OPT_NAOHTD         =  12.chr  # Output Horizontal Tab Disposition
  OPT_NAOFFD         =  13.chr  # Output Formfeed Disposition
  OPT_NAOVTS         =  14.chr  # Output Vertical Tabstops
  OPT_NAOVTD         =  15.chr  # Output Vertical Tab Disposition
  OPT_NAOLFD         =  16.chr  # Output Linefeed Disposition
  OPT_XASCII         =  17.chr  # Extended ASCII
  OPT_LOGOUT         =  18.chr  # Logout
  OPT_BM             =  19.chr  # Byte Macro
  OPT_DET            =  20.chr  # Data Entry Terminal
  OPT_SUPDUP         =  21.chr  # SUPDUP
  OPT_SUPDUPOUTPUT   =  22.chr  # SUPDUP Output
  OPT_SNDLOC         =  23.chr  # Send Location
  OPT_TTYPE          =  24.chr  # Terminal Type
  OPT_EOR            =  25.chr  # End of Record
  OPT_TUID           =  26.chr  # TACACS User Identification
  OPT_OUTMRK         =  27.chr  # Output Marking
  OPT_TTYLOC         =  28.chr  # Terminal Location Number
  OPT_3270REGIME     =  29.chr  # Telnet 3270 Regime
  OPT_X3PAD          =  30.chr  # X.3 PAD
  OPT_NAWS           =  31.chr  # Negotiate About Window Size
  OPT_TSPEED         =  32.chr  # Terminal Speed
  OPT_LFLOW          =  33.chr  # Remote Flow Control
  OPT_LINEMODE       =  34.chr  # Linemode
  OPT_XDISPLOC       =  35.chr  # X Display Location
  OPT_OLD_ENVIRON    =  36.chr  # Environment Option
  OPT_AUTHENTICATION =  37.chr  # Authentication Option
  OPT_ENCRYPT        =  38.chr  # Encryption Option
  OPT_NEW_ENVIRON    =  39.chr  # New Environment Option
  OPT_EXOPL          = 255.chr  # Extended-Options-List

  NULL = "\000"
  CR   = "\015"
  LF   = "\012"
  EOL  = CR + LF

  def initialize(options)
    @options = options
    @options["Binmode"]    = FALSE        if not @options.include?("Binmode")
    @options["Host"]       = "localhost"  if not @options.include?("Host")
    @options["Port"]       = 23           if not @options.include?("Port")
    @options["Prompt"]     = /[$%#>] \Z/  if not @options.include?("Prompt")
    @options["Telnetmode"] = TRUE         if not @options.include?("Telnetmode")
    @options["Timeout"]    = 10           if not @options.include?("Timeout")
    @options["Waittime"]   = 0            if not @options.include?("Waittime")

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

    message = "Trying " + @options["Host"] + "...\n"
    STDOUT.write(message)
    @log.write(message) if @options.include?("Output_log")
    @dumplog.write(message) if @options.include?("Dump_log")

    is_timeout = timeout(@options["Timeout"]){
      begin
        @sock = TCPsocket.open(@options["Host"], @options["Port"])
      rescue
        @log.write($! + "\n") if @options.include?("Output_log")
        @dumplog.write($! + "\n") if @options.include?("Dump_log")
        raise
      end
    }
    raise TimeOut, "timed-out; opening of the host" if is_timeout
    @sock.sync = TRUE
    @sock.binmode

    message = "Connected to " + @options["Host"] + ".\n"
    STDOUT.write(message)
    @log.write(message) if @options.include?("Output_log")
    @dumplog.write(message) if @options.include?("Dump_log")

    super(@sock)
  end

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

  def preprocess(str)

    if not @options["Binmode"]
      str.gsub!(/#{CR}#{NULL}/no, CR) # combine CR+NULL into CR
      str.gsub!(/#{EOL}/no, "\n")     # combine EOL into "\n"
    end

    # respond to "IAC DO x"
    str.gsub!(/(?:(?!#{IAC}))?#{IAC}#{DO}([#{OPT_BINARY}-#{OPT_NEW_ENVIRON}#{OPT_EXOPL}])/no){
      if OPT_BINARY == $1
        @telnet_option["BINARY"] = TRUE
        @sock.write(IAC + WILL + OPT_BINARY)
      else
        @sock.write(IAC + WONT + $1)
      end
      ''
    }

    # respond to "IAC DON'T x" with "IAC WON'T x"
    str.gsub!(/(?:(?!#{IAC}))?#{IAC}#{DONT}([#{OPT_BINARY}-#{OPT_NEW_ENVIRON}#{OPT_EXOPL}])/no){
      @sock.write(IAC + WONT + $1)
      ''
    }

    # respond to "IAC WILL x"
    str.gsub!(/(?:(?!#{IAC}))?#{IAC}#{WILL}([#{OPT_BINARY}-#{OPT_NEW_ENVIRON}#{OPT_EXOPL}])/no){
      if OPT_SGA == $1
        @telnet_option["SGA"] = TRUE
        @sock.write(IAC + DO + OPT_SGA)
      end
      ''
    }

    # ignore "IAC WON'T x"
    str.gsub!(/(?:(?!#{IAC}))?#{IAC}#{WONT}[#{OPT_BINARY}-#{OPT_NEW_ENVIRON}#{OPT_EXOPL}]/no, '')

    # respond to "IAC AYT" (are you there)
    str.gsub!(/(?:(?!#{IAC}))?#{IAC}#{AYT}/no){
      @sock.write("nobody here but us pigeons" + EOL)
      ''
    }

    str.gsub(/#{IAC}#{IAC}/no, IAC) # handle escaped IAC characters
  end

  def waitfor(options)
    timeout  = @options["Timeout"]
    waittime = @options["Waittime"]

    if options.kind_of?(Hash)
      prompt   = options["Prompt"]   if options.include?("Prompt")
      timeout  = options["Timeout"]  if options.include?("Timeout")
      waittime = options["Waittime"] if options.include?("Waittime")
      prompt   = Regexp.new( Regexp.quote(options["String"]) ) if
        options.include?("String")
    else
      prompt = options
    end

    line = ''
    until(not IO::select([@sock], nil, nil, waittime) and prompt === line)
      raise TimeOut, "timed-out; wait for the next data" if
        not IO::select([@sock], nil, nil, timeout)
      buf = ''
      begin
        buf = @sock.sysread(1024 * 1024)
        @dumplog.print(buf) if @options.include?("Dump_log")
        buf = preprocess(buf) if @options["Telnetmode"]
      rescue EOFError # End of file reached
        break
      ensure
        @log.print(buf) if @options.include?("Output_log")
        yield buf if iterator?
        line.concat(buf)
      end
    end
    line
  end

  def print(string)
    string.gsub!(/#{IAC}/no, IAC + IAC) if @options["Telnetmode"]
    if @options["Binmode"]
      @sock.write(string)
    else
      if @telnet_option["BINARY"] and @telnet_option["SGA"]
        # IAC WILL SGA IAC DO BIN send EOL --> CR
        @sock.write(string.gsub(/\n/, CR) + CR)
      elsif @telnet_option["SGA"]
        # IAC WILL SGA send EOL --> CR+NULL
        @sock.write(string.gsub(/\n/, CR + NULL) + CR + NULL)
      else
        # NONE send EOL --> LF
        @sock.write(string.gsub(/\n/, LF) + LF)
      end
    end
  end

  def cmd(options)
    match   = @options["Prompt"]
    timeout = @options["Timeout"]

    if options.kind_of?(Hash)
      string  = options["String"]
      match   = options["Match"]   if options.include?("Match")
      timeout = options["Timeout"] if options.include?("Timeout")
    else
      string = options
    end

    IO::select(nil, [@sock])
    print(string)
    if iterator?
      waitfor({"Prompt" => match, "Timeout" => timeout}){|c| yield c }
    else
      waitfor({"Prompt" => match, "Timeout" => timeout})
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
      line = waitfor(/login[: ]*\Z/){|c| yield c }
      line.concat( cmd({"String" => username,
                        "Match" => /Password[: ]*\Z/}){|c| yield c } )
      line.concat( cmd(password){|c| yield c } )
    else
      line = waitfor(/login[: ]*\Z/)
      line.concat( cmd({"String" => username,
                        "Match" => /Password[: ]*\Z/}) )
      line.concat( cmd(password) )
    end
    line
  end

end
