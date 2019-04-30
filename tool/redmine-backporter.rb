#!/usr/bin/env ruby
require 'open-uri'
require 'openssl'
require 'net/http'
require 'json'
require 'io/console'
require 'stringio'
require 'strscan'
require 'optparse'
require 'abbrev'
require 'pp'
require 'shellwords'
begin
  require 'readline'
rescue LoadError
  module Readline; end
end

VERSION = '0.0.1'

opts = OptionParser.new
target_version = nil
repo_path = nil
api_key = nil
ssl_verify = true
opts.on('-k REDMINE_API_KEY', '--key=REDMINE_API_KEY', 'specify your REDMINE_API_KEY') {|v| api_key = v}
opts.on('-t TARGET_VERSION', '--target=TARGET_VARSION', /\A\d(?:\.\d)+\z/, 'specify target version (ex: 2.1)') {|v| target_version = v}
opts.on('-r RUBY_REPO_PATH', '--repository=RUBY_REPO_PATH', 'specify repository path') {|v| repo_path = v}
opts.on('--[no-]ssl-verify', TrueClass, 'use / not use SSL verify') {|v| ssl_verify = v}
opts.version = VERSION
opts.parse!(ARGV)

http_options = {use_ssl: true}
http_options[:verify_mode] = OpenSSL::SSL::VERIFY_NONE unless ssl_verify
$openuri_options = {}
$openuri_options[:ssl_verify_mode] = OpenSSL::SSL::VERIFY_NONE unless ssl_verify

TARGET_VERSION = target_version || ENV['TARGET_VERSION'] || (raise 'need to specify TARGET_VERSION')
RUBY_REPO_PATH = repo_path || ENV['RUBY_REPO_PATH']
BACKPORT_CF_KEY = 'cf_5'
STATUS_CLOSE = 5
REDMINE_API_KEY = api_key || ENV['REDMINE_API_KEY'] || (raise 'need to specify REDMINE_API_KEY')
REDMINE_BASE = 'https://bugs.ruby-lang.org'

@query = {
  'f[]' => BACKPORT_CF_KEY,
  "op[#{BACKPORT_CF_KEY}]" => '~',
  "v[#{BACKPORT_CF_KEY}][]" => "#{TARGET_VERSION}: REQUIRED",
  'limit' => 40,
  'status_id' => STATUS_CLOSE,
  'sort' => 'updated_on'
}

PRIORITIES = {
  'Low' => [:white, :blue],
  'Normal' => [],
  'High' => [:red],
  'Urgent' => [:red, :white],
  'Immediate' => [:red, :white, {underscore: true}],
}
COLORS = {
  black: 30,
  red: 31,
  green: 32,
  yellow: 33,
  blue: 34,
  magenta: 35,
  cyan: 36,
  white: 37,
}

class String
  def color(fore=nil, back=nil, bold: false, underscore: false)
    seq = ""
    if bold
      seq << "\e[1m"
    end
    if underscore
      seq << "\e[2m"
    end
    if fore
      c = COLORS[fore]
      raise "unknown foreground color #{fore}" unless c
      seq << "\e[#{c}m"
    end
    if back
      c = COLORS[back]
      raise "unknown background color #{back}" unless c
      seq << "\e[#{c + 10}m"
    end
    if seq.empty?
      self
    else
      seq << self << "\e[0m"
    end
  end
end

class StringScanner
  # lx: limit of x (colmns of screen)
  # ly: limit of y (rows of screen)
  def getrows(lx, ly)
    cp1 = charpos
    x = 0
    y = 0
    until eos?
      case c = getch
      when "\r"
        x = 0
      when "\n"
        x = 0
        y += 1
      when "\t"
        x += 8
      when /[\x00-\x7f]/
        # halfwidth
        x += 1
      else
        # fullwidth
        x += 2
      end

      if x > lx
        x = 0
        y += 1
        unscan
      end
      if y >= ly
        return string[cp1...charpos]
      end
    end
    string[cp1..-1]
  end
end

def more(sio)
  console = IO.console
  ly, lx = console.winsize
  ly -= 1
  str = sio.string
  cls = "\r" + (" " * lx) + "\r"

  ss = StringScanner.new(str)

  rows = ss.getrows(lx, ly)
  puts rows
  until ss.eos?
    print ":"
    case c = console.getch
    when ' '
      rows = ss.getrows(lx, ly)
      puts cls + rows
    when 'j', "\r"
      rows = ss.getrows(lx, 1)
      puts cls + rows
    when "q"
      print cls
      break
    else
      print "\b"
    end
  end
end

class << Readline
  def readline(prompt = '')
    console = IO.console
    console.binmode
    _, lx = console.winsize
    if /mswin|mingw/ =~ RUBY_PLATFORM or /^(?:vt\d\d\d|xterm)/i =~ ENV["TERM"]
      cls = "\r\e[2K"
    else
      cls = "\r" << (" " * lx)
    end
    cls << "\r" << prompt
    console.print prompt
    console.flush
    line = ''
    while true
      case c = console.getch
      when "\r", "\n"
        puts
        HISTORY << line
        return line
      when "\C-?", "\b" # DEL/BS
        print "\b \b" if line.chop!
      when "\C-u"
        print cls
        line.clear
      when "\C-d"
        return nil if line.empty?
        line << c
      when "\C-p"
        HISTORY.pos -= 1
        line = HISTORY.current
        print cls
        print line
      when "\C-n"
        HISTORY.pos += 1
        line = HISTORY.current
        print cls
        print line
      else
        if c >= " "
          print c
          line << c
        end
      end
    end
  end

  HISTORY = []
  def HISTORY.<<(val)
    HISTORY.push(val)
    @pos = self.size
    self
  end
  def HISTORY.pos
    @pos ||= 0
  end
  def HISTORY.pos=(val)
    @pos = val
    if @pos < 0
      @pos = -1
    elsif @pos >= self.size
      @pos = self.size
    end
  end
  def HISTORY.current
    @pos ||= 0
    if @pos < 0 || @pos >= self.size
      ''
    else
      self[@pos]
    end
  end
end unless defined?(Readline.readline)

def find_svn_log(pattern)
  `svn log --xml --stop-on-copy --search="#{pattern}" #{RUBY_REPO_PATH}`
end

def find_git_log(pattern)
  `git #{RUBY_REPO_PATH ? "-C #{RUBY_REPO_PATH.shellecape}" : ""} log --grep="#{pattern}"`
end

def show_last_journal(http, uri)
  res = http.get("#{uri.path}?include=journals")
  res.value
  h = JSON(res.body)
  x = h["issue"]
  raise "no issue" unless x
  x = x["journals"]
  raise "no journals" unless x
  x = x.last
  puts "== #{x["user"]["name"]} (#{x["created_on"]})"
  x["details"].each do |y|
    puts JSON(y)
  end
  puts x["notes"]
end

def merger_path
  RUBY_PLATFORM =~ /mswin|mingw/ ? 'merger' : File.expand_path('../merger.rb', __FILE__)
end

def backport_command_string
  unless @changesets.respond_to?(:validated)
    @changesets = @changesets.select do |c|
      next false if c.match(/\A\d{1,6}\z/) # skip SVN revision

      # check if the Git revision is included in trunk
      begin
        uri = URI("#{REDMINE_BASE}/projects/ruby-trunk/repository/ruby-git/revisions/#{c}")
        uri.read($openuri_options)
        true
      rescue
        false
      end
    end
    @changesets.define_singleton_method(:validated){true}
  end
  " #{merger_path} --ticket=#{@issue} #{@changesets.sort.join(',')}"
end

def status_char(obj)
  case obj["name"]
  when "Closed"
    "C".color(bold: true)
  else
    obj["name"][0]
  end
end

console = IO.console
row, = console.winsize
@query['limit'] = row - 2
puts "Backporter #{VERSION}".color(bold: true) + " for #{TARGET_VERSION}"

class CommandSyntaxError < RuntimeError; end
commands = {
  "ls" => proc{|args|
    raise CommandSyntaxError unless /\A(\d+)?\z/ =~ args
    uri = URI(REDMINE_BASE+'/projects/ruby-trunk/issues.json?'+URI.encode_www_form(@query.dup.merge('page' => ($1 ? $1.to_i : 1))))
    # puts uri
    res = JSON(uri.read($openuri_options))
    @issues = issues = res["issues"]
    from = res["offset"] + 1
    total = res["total_count"]
    to = from + issues.size - 1
    puts "#{from}-#{to} / #{total}"
    issues.each_with_index do |x, i|
      id = "##{x["id"]}".color(*PRIORITIES[x["priority"]["name"]])
      puts "#{'%2d' % i} #{id} #{x["priority"]["name"][0]} #{status_char(x["status"])} #{x["subject"][0,80]}"
    end
  },

  "show" => proc{|args|
    if /\A(\d+)\z/ =~ args
      id = $1.to_i
      id = @issues[id]["id"] if @issues && id < @issues.size
      @issue = id
    elsif @issue
      id = @issue
    else
      raise CommandSyntaxError
    end
    uri = "#{REDMINE_BASE}/issues/#{id}"
    uri = URI(uri+".json?include=children,attachments,relations,changesets,journals")
    res = JSON(uri.read($openuri_options))
    i = res["issue"]
    unless i["changesets"]
      abort "You don't have view_changesets permission"
    end
    unless i["custom_fields"]
      puts "The specified ticket \##{@issue} seems to be a feature ticket"
      @issue = nil
      next
    end
    id = "##{i["id"]}".color(*PRIORITIES[i["priority"]["name"]])
    sio = StringIO.new
    sio.set_encoding("utf-8")
    sio.puts <<eom
#{i["subject"].color(bold: true, underscore: true)}
#{i["project"]["name"]} [#{i["tracker"]["name"]} #{id}] #{i["status"]["name"]} (#{i["created_on"]})
author:   #{i["author"]["name"]}
assigned: #{i["assigned_to"].to_h["name"]}
eom
    i["custom_fields"].each do |x|
      sio.puts "%-10s: %s" % [x["name"], x["value"]]
    end
    #res["attachements"].each do |x|
    #end
    sio.puts i["description"]
    sio.puts
    sio.puts "= changesets".color(bold: true, underscore: true)
    @changesets = []
    i["changesets"].each do |x|
      @changesets << x["revision"]
      sio.puts "== #{x["revision"]} #{x["committed_on"]} #{x["user"]["name"] rescue nil}".color(bold: true, underscore: true)
      sio.puts x["comments"]
    end
    @changesets = @changesets.sort.uniq
    if i["journals"] && !i["journals"].empty?
      sio.puts "= journals".color(bold: true, underscore: true)
      i["journals"].each do |x|
        sio.puts "== #{x["user"]["name"]} (#{x["created_on"]})".color(bold: true, underscore: true)
        x["details"].each do |y|
          sio.puts JSON(y)
        end
        sio.puts x["notes"]
      end
    end
    more(sio)
  },

  "rel" => proc{|args|
    # this feature requires custom redmine which allows add_related_issue API
    case args
    when /\Ar?(\d+)\z/ # SVN
      rev = $1
      uri = URI("#{REDMINE_BASE}/projects/ruby-trunk/repository/trunk/revisions/#{rev}/issues.json")
    when /\A\h{7,40}\z/ # Git
      rev = args
      uri = URI("#{REDMINE_BASE}/projects/ruby-trunk/repository/ruby-git/revisions/#{rev}/issues.json")
    else
      raise CommandSyntaxError
    end
    unless @issue
      puts "ticket not selected"
      next
    end

    Net::HTTP.start(uri.host, uri.port, http_options) do |http|
      res = http.post(uri.path, "issue_id=#@issue",
                     'X-Redmine-API-Key' => REDMINE_API_KEY)
      begin
        res.value
      rescue
        if $!.respond_to?(:response) && $!.response.is_a?(Net::HTTPConflict)
          $stderr.puts "the revision has already related to the ticket"
        else
          $stderr.puts "#{$!.class}: #{$!.message}\n\ndeployed redmine doesn't have https://github.com/ruby/bugs.ruby-lang.org/commit/01fbba60d68cb916ddbccc8a8710e68c5217171d\nask naruse or hsbt"
        end
        next
      end
      puts res.body
      @changesets << rev
      class << @changesets
        remove_method(:validated) rescue nil
      end
    end
  },

  "backport" => proc{|args|
    # this feature implies backport command which wraps tool/merger.rb
    raise CommandSyntaxError unless args.empty?
    unless @issue
      puts "ticket not selected"
      next
    end
    puts backport_command_string
  },

  "done" => proc{|args|
    raise CommandSyntaxError unless /\A(\d+)?(?:\s*-- +(.*))?\z/ =~ args
    notes = $2
    notes.strip! if notes
    if $1
      i = $1.to_i
      i = @issues[i]["id"] if @issues && i < @issues.size
      @issue = i
    end
    unless @issue
      puts "ticket not selected"
      next
    end

    if system("svn info #{RUBY_REPO_PATH&.shellescape}", %i(out err) => IO::NULL) # SVN
      if log = find_svn_log("##@issue]") && /revision="(?<rev>\d+)/ =~ log
        rev = "r#{rev}"
      end
    else # Git
      if log = find_git_log("##@issue]")
        /^commit (?<rev>\h{40})$/ =~ log
      end
    end
    if log && rev
      str = log[/merge revision\(s\) ([^:]+)(?=:)/]
      str.insert(5, "d")
      str = "ruby_#{TARGET_VERSION.tr('.','_')} #{rev} #{str}."
      if notes
        str << "\n"
        str << notes
      end
      notes = str
    else
      puts "no commit is found whose log include ##@issue"
      next
    end
    puts notes

    uri = URI("#{REDMINE_BASE}/issues/#{@issue}.json")
    Net::HTTP.start(uri.host, uri.port, http_options) do |http|
      res = http.get(uri.path)
      data = JSON(res.body)
      h = data["issue"]["custom_fields"].find{|x|x["id"]==5}
      if h and val = h["value"] and val != ""
        case val[/(?:\A|, )#{Regexp.quote TARGET_VERSION}: ([^,]+)/, 1]
        when 'REQUIRED', 'UNKNOWN', 'DONTNEED', 'WONTFIX'
          val[$~.offset(1)[0]...$~.offset(1)[1]] = 'DONE'
        when 'DONE' # , /\A\d+\z/
          puts 'already backport is done'
          next # already done
        when nil
          val << ", #{TARGET_VERSION}: DONE"
        else
          raise "unknown status '#$1'"
        end
      else
        val = "#{TARGET_VERSION}: DONE"
      end

      data = { "issue" => { "custom_fields" => [ {"id"=>5, "value" => val} ] } }
      data['issue']['notes'] = notes if notes
      res = http.put(uri.path, JSON(data),
                     'X-Redmine-API-Key' => REDMINE_API_KEY,
                     'Content-Type' => 'application/json')
      res.value

      show_last_journal(http, uri)
    end
  },

  "close" => proc{|args|
    raise CommandSyntaxError unless /\A(\d+)?\z/ =~ args
    if $1
      i = $1.to_i
      i = @issues[i]["id"] if @issues && i < @issues.size
      @issue = i
    end
    unless @issue
      puts "ticket not selected"
      next
    end

    uri = URI("#{REDMINE_BASE}/issues/#{@issue}.json")
    Net::HTTP.start(uri.host, uri.port, http_options) do |http|
      data = { "issue" => { "status_id" => STATUS_CLOSE } }
      res = http.put(uri.path, JSON(data),
                     'X-Redmine-API-Key' => REDMINE_API_KEY,
                     'Content-Type' => 'application/json')
      res.value

      show_last_journal(http, uri)
    end
  },

  "last" => proc{|args|
    raise CommandSyntaxError unless /\A(\d+)?\z/ =~ args
    if $1
      i = $1.to_i
      i = @issues[i]["id"] if @issues && i < @issues.size
      @issue = i
    end
    unless @issue
      puts "ticket not selected"
      next
    end

    uri = URI("#{REDMINE_BASE}/issues/#{@issue}.json")
    Net::HTTP.start(uri.host, uri.port, http_options) do |http|
      show_last_journal(http, uri)
    end
  },

  "!" => proc{|args|
    system(args.strip)
  },

  "quit" => proc{|args|
    raise CommandSyntaxError unless args.empty?
    exit
  },
  "exit" => "quit",

  "help" => proc{|args|
    puts 'ls [PAGE]              '.color(bold: true) + ' show all required tickets'
    puts '[show] TICKET          '.color(bold: true) + ' show the detail of the TICKET, and select it'
    puts 'backport               '.color(bold: true) + ' show the option of selected ticket for merger.rb'
    puts 'rel REVISION           '.color(bold: true) + ' add the selected ticket as related to the REVISION'
    puts 'done [TICKET] [-- NOTE]'.color(bold: true) + ' set Backport field of the TICKET to DONE'
    puts 'close [TICKET]         '.color(bold: true) + ' close the TICKET'
    puts 'last [TICKET]          '.color(bold: true) + ' show the last journal of the TICKET'
    puts '! COMMAND              '.color(bold: true) + ' execute COMMAND'
  }
}
list = Abbrev.abbrev(commands.keys)

@issues = nil
@issue = nil
@changesets = nil
while true
  begin
    l = Readline.readline "#{('#' + @issue.to_s).color(bold: true) if @issue}> "
  rescue Interrupt
    break
  end
  break unless l
  cmd, args = l.strip.split(/\s+|\b/, 2)
  next unless cmd
  if (!args || args.empty?) && /\A\d+\z/ =~ cmd
    args = cmd
    cmd = "show"
  end
  cmd = list[cmd]
  if commands[cmd].is_a? String
    cmd = list[commands[cmd]]
  end
  begin
    if cmd
      commands[cmd].call(args)
    else
      raise CommandSyntaxError
    end
  rescue CommandSyntaxError
    puts "error #{l.inspect}"
  end
end
