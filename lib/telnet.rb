#
# telnet.rb
# ver0.11 1998/04/21
# Wakou Aoyama <wakou@fsinet.or.jp>
#
# == make new Telnet object
# host = Telnet.new("Binmode" => TRUE,              default: TRUE
#                   "Host" => "localhost",          default: "localhost"
#                   "Output_log" => "output_log",   default: not output
#                   "Port" => 23,                   default: 23
#                   "Prompt" => /[$%#>] $/,         default: /[$%#>] $/
#                   "Telnetmode" => TRUE,           default: TRUE
#                   "Timeout" => 10)                default: 10
#
# if set "Telnetmode" option FALSE. not TELNET command interpretation.
#
# == wait for match
# print host.waitfor(/match/)
# print host.waitfor("Match"   => /match/,
#                    "String"  => "string",
#                    "Timeout" => secs)
# if set "String" option. Match = Regexp.new(quote(string))
#
# realtime output. of cource, set sync=TRUE or flush is necessary.
# host.waitfor(/match/){|c| print c }
# host.waitfor("Match"   => /match/,
#              "String"  => "string",
#              "Timeout" => secs){|c| print c}
#
# == send string and wait prompt
# print host.cmd("string")
# print host.cmd("String" => "string",
#                "Prompt" => /[$%#>] $//,
#                "Timeout" => 10)
#
# realtime output. of cource, set sync=TRUE or flush is necessary.
# host.cmd("string"){|c| print c }
# host.cmd("String" => "string",
#          "Prompt" => /[$%#>] $//,
#          "Timeout" => 10){|c| print c }
#
# == login
# host.login("username", "password")
# host.login("Name" => "username",
#            "Password" => "password",
#            "Prompt" => /[$%#>] $/,
#            "Timeout" => 10)
#
# and Telnet object has socket class methods
#
# == sample
# localhost = Telnet.new("Host" => "localhost",
#                        "Timeout" => 10,
#                        "Prompt" => /[$%#>] $/)
# localhost.login("username", "password")
# print localhost.cmd("command")
# localhost.close

require "socket"
require "delegate"

class Telnet < SimpleDelegator
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
    @options = {}
    @options["Binmode"] = options["Binmode"] || TRUE
    @options["Dump_Log"] = options["Dump_Log"]
    @options["Errmode"] = options["Errmode"]
    @options["Fhopen"] = options["Fhopen"]
    @options["Host"] = options["Host"] || "localhost"
    @options["Input_log"] = options["Input_log"]
    @options["Input_record_separator"] = options["Input_record_separator"]
    @options["Output_log"] = options["Output_log"]
    @options["Output_record_separator"] = options["Output_record_separator"]
    @options["Port"] = options["Port"] || 23
    @options["Prompt"] = options["Prompt"] || /[$%#>] $/
    @options["Telnetmode"] = options["Telnetmode"] || TRUE
    @options["Timeout"] = options["Timeout"] || 10

    if @options.include?("Output_log")
      @log = File.open(@options["Output_log"], 'a+')
      @log.sync = TRUE
      @log.binmode if @options["Binmode"]
    end
    @sock = TCPsocket.open(@options["Host"], @options["Port"])
    @sock.sync = TRUE
    @sock.binmode if @options["Binmode"]
    super(@sock)
  end

  def preprocess(str)
    str.gsub!(/#{EOL}/no, "\n") # combine EOL into "\n"

    # respond to "IAC DO x" or "IAC DON'T x" with "IAC WON'T x"
    str.gsub!(/([^#{IAC}])?#{IAC}[#{DO}#{DONT}](.|\n)/no){
        @sock << IAC << WONT << $2
        $1
    }

    # ignore "IAC WILL x" or "IAC WON'T x"
    str.gsub!(/([^#{IAC}])?#{IAC}[#{WILL}#{WONT}](.|\n)/no, '\1')

    # respond to "IAC AYT" (are you there)
    str.gsub!(/([^#{IAC}])?#{IAC}#{AYT}/no){
        @sock << "nobody here but us pigeons" << CR
        $1
    }

    str.gsub(/#{IAC}#{IAC}/no, IAC) # handle escaped IAC characters
  end

  def waitfor(options)
    prompt = @options["Prompt"]
    timeout = @options["Timeout"]
    if options.kind_of?(Hash)
      prompt = options["Prompt"] if options.include?("Prompt")
      timeout = options["Timeout"] if options.include?("Timeout")
      prompt = Regexp.new( Regexp.quote(options["String"]) ) if
        options.include?("String")
    else
      prompt = options
    end
    line = ''
    while (not prompt === line and not @sock.closed?)
      next if not select([@sock], nil, nil, timeout)
      begin
        buf = if @options["Telnetmode"]
                preprocess( @sock.sysread(1024 * 1024) )
              else
                @sock.sysread(1024 * 1024)
              end
      rescue
        buf = "\nConnection closed by foreign host.\n"
        @sock.close
      end
      @log.print(buf) if @options.include?("Output_log")
      if iterator?
        yield buf
      end
      line += buf
    end
    line
  end

  def cmd(options)
    match = @options["Prompt"]
    timeout = @options["Timeout"]
    if options.kind_of?(Hash)
      string = options["String"]
      match = options["Match"] if options.include?("Match")
      timeout = options["Timeout"] if options.include?("Timeout")
    else
      string = options
    end
    @sock << string.gsub(/\n/, CR) << CR
    if iterator?
      waitfor({"Prompt" => match, "Timeout" => timeout}){|c| yield c }
    else
      waitfor({"Prompt" => match, "Timeout" => timeout})
    end
  end

  def login(options, password = nil)
    if options.kind_of?(Hash)
      username = options["Name"]
      password = options["Password"]
    else
      username = options
    end

    line = waitfor(/login[: ]*$/)
    line += cmd({"String" => username, "Match" => /Password[: ]*$/})
    line += cmd(password)
    line
  end

end
