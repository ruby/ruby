#
# telnet.rb
# ver0.13 1998/08/25
# Wakou Aoyama <wakou@fsinet.or.jp>
#
# ver0.13 1998/08/25
# add print method.
#
# ver0.122 1998/08/05
# support for HP-UX 10.20    thanks to WATANABE Tetsuya <tetsu@jpn.hp.com>
# socket.<< --> socket.write
#
# ver0.121 1998/07/15
# string.+= --> string.concat
#
# ver0.12 1998/06/01
# add timeout, waittime.
#
# ver0.11 1998/04/21
# add realtime output.
#
# ver0.10 1998/04/13
# first release.
#
# == make new Telnet object
# host = Telnet.new({"Binmode" => TRUE,              default: TRUE
#                    "Host" => "localhost",          default: "localhost"
#                    "Output_log" => "output_log",   default: not output
#                    "Port" => 23,                   default: 23
#                    "Prompt" => /[$%#>] $/,         default: /[$%#>] $/
#                    "Telnetmode" => TRUE,           default: TRUE
#                    "Timeout" => 10,                default: 10
#                    "Waittime" => 0})               default: 0
#
# if set "Telnetmode" option FALSE. not TELNET command interpretation.
# "Waittime" is time to confirm "Prompt". There is a possibility that
# the same character as "Prompt" is included in the data, and, when
# the network or the host is very heavy, the value is enlarged.
#
# == wait for match
# line = host.waitfor(/match/)
# line = host.waitfor({"Match"   => /match/,
#                      "String"  => "string",
#                      "Timeout" => secs})
# if set "String" option. Match = Regexp.new(quote(string))
#
# realtime output. of cource, set sync=TRUE or flush is necessary.
# host.waitfor(/match/){|c| print c }
# host.waitfor({"Match"   => /match/,
#               "String"  => "string",
#               "Timeout" => secs}){|c| print c}
#
# == send string and wait prompt
# line = host.cmd("string")
# line = host.cmd({"String" => "string",
#                  "Prompt" => /[$%#>] $//,
#                  "Timeout" => 10})
#
# realtime output. of cource, set sync=TRUE or flush is necessary.
# host.cmd("string"){|c| print c }
# host.cmd({"String" => "string",
#           "Prompt" => /[$%#>] $//,
#           "Timeout" => 10}){|c| print c }
#
# == send string
# host.print("string")
#
# == login
# host.login("username", "password")
# host.login({"Name" => "username",
#             "Password" => "password",
#             "Prompt" => /[$%#>] $/,
#             "Timeout" => 10})
#
# realtime output. of cource, set sync=TRUE or flush is necessary.
# host.login("username", "password"){|c| print c }
# host.login({"Name" => "username",
#             "Password" => "password",
#             "Prompt" => /[$%#>] $/,
#             "Timeout" => 10}){|c| print c }
#
# and Telnet object has socket class methods
#
# == sample
# localhost = Telnet.new({"Host" => "localhost",
#                         "Timeout" => 10,
#                         "Prompt" => /[$%#>] $/})
# localhost.login("username", "password"){|c| print c }
# localhost.cmd("command"){|c| print c }
# localhost.close
#
# == sample 2
# checks a POP server to see if you have mail.
#
# pop = Telnet.new({"Host" => "your_destination_host_here",
#                   "Port" => 110,
#                   "Telnetmode" => FALSE,
#                   "Prompt" => /^\+OK/})
# pop.cmd("user " + "your_username_here"){|c| print c}
# pop.cmd("pass " + "your_password_here"){|c| print c}
# pop.cmd("list"){|c| print c}

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

  # For those who are curious, here are some of the special characters
  # interpretted by the telnet protocol:
  # Name     Octal    Dec.  Description
    CR    = "\015"
    LF    = "\012"
    EOL   = CR + LF #       /* end of line */
    IAC   = "\377"  # 255   /* interpret as command: */
    DONT  = "\376"  # 254   /* you are not to use option */
    DO    = "\375"  # 253   /* please, you use option */
    WONT  = "\374"  # 252   /* I won't use option */
    WILL  = "\373"  # 251   /* I will use option */
  # SB    = "\372"  # 250   /* interpret as subnegotiation */
  # GA    = "\371"  # 249   /* you may reverse the line */
  # EL    = "\370"  # 248   /* erase the current line */
  # EC    = "\367"  # 247   /* erase the current character */
    AYT   = "\366"  # 246   /* are you there */
  # AO    = "\365"  # 245   /* abort output--but let prog finish */
  # IP    = "\364"  # 244   /* interrupt process--permanently */
  # BREAK = "\363"  # 243   /* break */
  # DM    = "\362"  # 242   /* data mark--for connect. cleaning */
  # NOP   = "\361"  # 241   /* nop */
  # SE    = "\360"  # 240   /* end sub negotiation */
  # EOR   = "\357"  # 239   /* end of record (transparent mode) */

  def initialize(options)
    @options = options
    @options["Binmode"]    = TRUE        if not @options.include?("Binmode")
    @options["Host"]       = "localhost" if not @options.include?("Host")
    @options["Port"]       = 23          if not @options.include?("Port")
    @options["Prompt"]     = /[$%#>] $/  if not @options.include?("Prompt")
    @options["Telnetmode"] = TRUE        if not @options.include?("Telnetmode")
    @options["Timeout"]    = 10          if not @options.include?("Timeout")
    @options["Waittime"]   = 0           if not @options.include?("Waittime")

    if @options.include?("Output_log")
      @log = File.open(@options["Output_log"], 'a+')
      @log.sync = TRUE
      @log.binmode if @options["Binmode"]
    end

    message = "Trying " + @options["Host"] + "...\n"
    STDOUT.write(message)
    @log.write(message) if @options.include?("Output_log")

    is_timeout = timeout(@options["Timeout"]){
      begin
        @sock = TCPsocket.open(@options["Host"], @options["Port"])
      rescue
        @log.write($! + "\n") if @options.include?("Output_log")
        raise
      end
    }
    raise TimeOut, "timed-out; opening of the host" if is_timeout
    @sock.sync = TRUE
    @sock.binmode if @options["Binmode"]

    message = "Connected to " + @options["Host"] + ".\n"
    STDOUT.write(message)
    @log.write(message) if @options.include?("Output_log")

    super(@sock)
  end

  def preprocess(str)
    str.gsub!(/#{EOL}/no, "\n") # combine EOL into "\n"

    # respond to "IAC DO x" or "IAC DON'T x" with "IAC WON'T x"
    str.gsub!(/([^#{IAC}])?#{IAC}[#{DO}#{DONT}](.|\n)/no){
        @sock.write(IAC + WONT + $2)
        $1
    }

    # ignore "IAC WILL x" or "IAC WON'T x"
    str.gsub!(/([^#{IAC}])?#{IAC}[#{WILL}#{WONT}](.|\n)/no, '\1')

    # respond to "IAC AYT" (are you there)
    str.gsub!(/([^#{IAC}])?#{IAC}#{AYT}/no){
        @sock.write("nobody here but us pigeons" + EOL)
        $1
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
    until(not select([@sock], nil, nil, waittime) and prompt === line)
      raise TimeOut, "timed-out; wait for the next data" if
        not select([@sock], nil, nil, timeout)
      buf = ''
      begin
        buf = if @options["Telnetmode"]
                preprocess( @sock.sysread(1024 * 1024) )
              else
                @sock.sysread(1024 * 1024)
              end
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
    @sock.write(string.gsub(/\n/, EOL) + EOL)
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

    select(nil, [@sock])
    @sock.write(string.gsub(/\n/, EOL) + EOL)
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
      line = waitfor(/login[: ]*$/){|c| yield c }
      line.concat( cmd({"String" => username,
                        "Match" => /Password[: ]*$/}){|c| yield c } )
      line.concat( cmd(password){|c| yield c } )
    else
      line = waitfor(/login[: ]*$/)
      line.concat( cmd({"String" => username,
                        "Match" => /Password[: ]*$/}) )
      line.concat( cmd(password) )
    end
    line
  end

end
