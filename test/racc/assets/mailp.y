#
# mailp for test
#

class Testp

rule

  content   : DateH         datetime   { @field.date  = val[1] }
            | RecvH         received
            | RetpathH      returnpath
            | MaddrH        addrs      { @field.addrs.replace val[1] }
            | SaddrH        addr       { @field.addr  = val[1] }
            | MmboxH        mboxes     { @field.addrs.replace val[1] }
            | SmboxH        mbox       { @field.addr  = val[1] }
            | MsgidH        msgid      { @field.msgid = val[1] }
            | KeyH          keys       { @field.keys.replace val[1] }
            | EncH          enc
            | VersionH      version
            | CTypeH        ctype
            | CEncodingH    cencode
            | CDispositionH cdisp
            | Mbox          mbox
                {
                  mb = val[1]
                  @field.phrase = mb.phrase
                  @field.setroute mb.route
                  @field.local  = mb.local
                  @field.domain = mb.domain
                }
            | Spec          spec
                {
                  mb = val[1]
                  @field.local  = mb.local
                  @field.domain = mb.domain
                }
            ;

  datetime  : day DIGIT ATOM DIGIT hour zone
            # 0   1     2    3     4    5
            #     day  month year
                {
                  t = Time.gm( val[3].to_i, val[2], val[1].to_i, 0, 0, 0 )
                  result = (t + val[4] - val[5]).localtime
                }
            ;

  day       :  /* none */
            | ATOM ','
            ;

  hour      : DIGIT ':' DIGIT
                {
                  result = (result.to_i * 60 * 60) + (val[2].to_i * 60)
                }
            | DIGIT ':' DIGIT ':' DIGIT
                {
                  result = (result.to_i * 60 * 60) +
                           (val[2].to_i * 60)
                           + val[4].to_i
                }
            ;

  zone      : ATOM
                {
                  result = ::TMail.zonestr2i( val[0] ) * 60
                }
            ;

  received  : from by via with id for recvdatetime
            ;

  from      : /* none */
            | FROM domain
                {
                  @field.from = Address.join( val[1] )
                }
            | FROM domain '@' domain
                {
                  @field.from = Address.join( val[3] )
                }
            | FROM domain DOMLIT
                {
                  @field.from = Address.join( val[1] )
                }
            ;

  by        :  /* none */
            | BY domain
                {
                  @field.by = Address.join( val[1] )
                }
            ;

  via       :  /* none */
            | VIA ATOM
                {
                  @field.via = val[1]
                }
            ;

  with      : /* none */
            | WITH ATOM
                {
                  @field.with.push val[1]
                }
            ;

  id        :  /* none */
            | ID msgid
                {
                  @field.msgid = val[1]
                }
            | ID ATOM
                {
                  @field.msgid = val[1]
                }
            ;

  for       :  /* none */
            | FOR addr
                {
                  @field.for_ = val[1].address
                }
            ;

  recvdatetime
            :  /* none */
            | ';' datetime
                {
                  @field.date = val[1]
                }
            ;

  returnpath: '<' '>'
            | routeaddr
                {
                  @field.route.replace result.route
                  @field.addr = result.addr
                }
            ;

  addrs     : addr           { result = val }
            | addrs ',' addr { result.push val[2] }
            ;

  addr      : mbox
            | group
            ;

  mboxes    : mbox
                {
                  result = val
                }
            | mboxes ',' mbox
                {
                  result.push val[2]
                }
            ;

  mbox      : spec
            | routeaddr
            | phrase routeaddr
                {
                  val[1].phrase = HFdecoder.decode( result )
                  result = val[1]
                }
            ;

  group     : phrase ':' mboxes ';'
                {
                  result = AddressGroup.new( result, val[2] )
                }
          # |    phrase ':' ';' { result = AddressGroup.new( result ) }
            ;

  routeaddr : '<' route spec '>'
                {
                  result = val[2]
                  result.route = val[1]
                }
            | '<' spec '>'
                {
                  result = val[1]
                }
            ;

  route     : at_domains ':'
            ;

  at_domains: '@' domain                { result = [ val[1] ] }
            | at_domains ',' '@' domain { result.push val[3] }
            ;

  spec      : local '@' domain { result = Address.new( val[0], val[2] ) }
            | local            { result = Address.new( result, nil ) }
            ;

  local     : word           { result = val }
            | local '.' word { result.push val[2] }
            ;

  domain    : domword            { result = val }
            | domain '.' domword { result.push val[2] }
            ;

  domword   : atom
            | DOMLIT
            | DIGIT
            ;

  msgid     : '<' spec '>'
                {
                  val[1] = val[1].addr
                  result = val.join('')
                }
            ;

  phrase    : word
            | phrase word { result << ' ' << val[1] }
            ;

  word      : atom
            | QUOTED
            | DIGIT
            ;

  keys      : phrase
            | keys ',' phrase
            ;

  enc       : word
                {
                  @field.encrypter = val[0]
                }
            | word word
                {
                  @field.encrypter = val[0]
                  @field.keyword   = val[1]
                }
            ;

  version   : DIGIT '.' DIGIT
                {
                  @field.major = val[0].to_i
                  @field.minor = val[2].to_i
                }
            ;

  ctype     : TOKEN '/' TOKEN params
                {
                  @field.main = val[0]
                  @field.sub  = val[2]
                }
            | TOKEN params
                {
                  @field.main = val[0]
                  @field.sub  = ''
                }
            ;

  params    : /* none */
            | params ';' TOKEN '=' value
                {
                  @field.params[ val[2].downcase ] = val[4]
                }
            ;

  value     : TOKEN
            | QUOTED
            ;

  cencode   : TOKEN
                {
                  @field.encoding = val[0]
                }
            ;

  cdisp     : TOKEN disp_params
                {
                  @field.disposition = val[0]
                }
            ;

  disp_params
            :  /* none */
            | disp_params ';' disp_param
            ;

  disp_param: /* none */
            | TOKEN '=' value
                {
                  @field.params[ val[0].downcase ] = val[2]
                }
            ;

  atom      : ATOM
            | FROM
            | BY
            | VIA
            | WITH
            | ID
            | FOR
            ;

end


---- header
#
# mailp for test
#

require 'tmail/mails'


module TMail

---- inner

  MAILP_DEBUG = false

  def initialize
    self.debug = MAILP_DEBUG
  end

  def debug=( flag )
    @yydebug = flag && Racc_debug_parser
    @scanner_debug = flag
  end

  def debug
    @yydebug
  end


  def Mailp.parse( str, obj, ident )
    new.parse( str, obj, ident )
  end


  NATIVE_ROUTINE = {
    'TMail::MsgidH' => :msgid_parse,
    'TMail::RefH' => :refs_parse
  }

  def parse( str, obj, ident )
    return if /\A\s*\z/ === str

    @field = obj

    if mid = NATIVE_ROUTINE[ obj.type.name ] then
      send mid, str
    else
      unless ident then
        ident = obj.type.name.split('::')[-1].to_s
        cmt = []
        obj.comments.replace cmt
      else
        cmt = nil
      end

      @scanner = MailScanner.new( str, ident, cmt )
      @scanner.debug = @scanner_debug
      @first = [ ident.intern, ident ]
      @pass_array = [nil, nil]

      do_parse
    end
  end


  private


  def next_token
    if @first then
      ret = @first
      @first = nil
      ret
    else
      @scanner.scan @pass_array
    end
  end

  def on_error( tok, val, vstack )
    raise ParseError,
      "\nparse error in '#{@field.name}' header, on token #{val.inspect}"
  end



  def refs_parse( str )
    arr = []

    while mdata = ::TMail::MSGID.match( str ) do
      str = mdata.post_match

      pre = mdata.pre_match
      pre.strip!
      proc_phrase pre, arr unless pre.empty?
      arr.push mdata.to_s
    end
    str.strip!
    proc_phrase str, arr if not pre or pre.empty?

    @field.refs.replace arr
  end

  def proc_phrase( str, arr )
    while mdata = /"([^\\]*(?:\\.[^"\\]*)*)"/.match( str ) do
      str = mdata.post_match

      pre = mdata.pre_match
      pre.strip!
      arr.push pre unless pre.empty?
      arr.push mdata[1]
    end
    str.strip!
    arr.push unless str.empty?
  end


  def msgid_parse( str )
    if mdata = ::TMail::MSGID.match( str ) then
      @field.msgid = mdata.to_s
    else
      raise ParseError, "wrong Message-ID format: #{str}"
    end
  end

---- footer

end   # module TMail

mp = TMail::Testp.new
mp.parse
