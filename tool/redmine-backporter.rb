#!/usr/bin/env ruby
require 'open-uri'
require 'net/http'
require 'json'
require 'io/console'
require 'stringio'
require 'strscan'
require 'pp'

TARGET_VERSION = ENV['TARGET_VERSION']
RUBY_REPO_PATH = ENV['RUBY_REPO_PATH']
BACKPORT_CF_KEY = 'cf_5'
STATUS_CLOSE = 5
REDMINE_API_KEY = ENV['REDMINE_API_KEY']
REDMINE_BASE = 'https://bugs.ruby-lang.org'

VERSION = '0.0.1'
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
      seq << "\e[#{c}m"
    end
    if seq.empty?
      self
    else
      seq << self << "\e[0m"
    end
  end
end

def wcwidth(wc)
  return 8 if wc == "\t"
  n = wc.ord
  if n < 0x20
    0
  elsif n < 0x80
    1
  else
    2
  end
end

def fold(str, col)
  i = 0
  size = str.size
  len = 0
  while i < size
    case c = str[i]
    when "\r", "\n"
      len = 0
    else
      d = wcwidth(c)
      len += d
      if len == col
        str.insert(i+1, "\n")
        len = 0
        i += 2
        next
      elsif len > col
        str.insert(i, "\n")
        len = d
        i += 2
        next
      end
    end
    i += 1
  end
  str
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
    when ' ', "\x04"
      rows = ss.getrows(lx, ly)
      puts cls + rows
    when 'j', ""
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

def mergeinfo
  `svn propget svn:mergeinfo #{RUBY_REPO_PATH}`
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

def backport_command_string
  "backport --ticket=#{@issue} #{@changesets.join(',')}"
end

console = IO.console
row, col = console.winsize
@query['limit'] = row - 2
puts "Backporter #{VERSION}".color(bold: true) + " for #{TARGET_VERSION}"

@issues = nil
@issue = nil
@changesets = nil
while true
  print '> '
  begin
    l = gets
  rescue Interrupt
    break
  end
  l.strip! if l
  case l
  when 'ls'
    uri = URI(REDMINE_BASE+'/projects/ruby-trunk/issues.json?'+URI.encode_www_form(@query))
    # puts uri
    res = JSON(uri.read)
    @issues = issues = res["issues"]
    from = res["offset"] + 1
    total = res["total_count"]
    to = from + issues.size - 1
    puts "#{from}-#{to} / #{total}"
    issues.each_with_index do |x, i|
      id = "##{x["id"]}".color(*PRIORITIES[x["priority"]["name"]])
      puts "#{'%2d' % i} #{id} #{x["priority"]["name"][0]} #{x["status"]["name"][0]} #{x["subject"][0,80]}"
    end
  when /\A(?:show +)?(\d+)\z/
    id = $1.to_i
    id = @issues[id]["id"] if @issues && id < @issues.size
    @issue = id
    uri = "#{REDMINE_BASE}/issues/#{id}"
    uri = URI(uri+".json?include=children,attachments,relations,changesets,journals")
    res = JSON(uri.read)
    i = res["issue"]
    id = "##{i["id"]}".color(*PRIORITIES[i["priority"]["name"]])
    sio = StringIO.new
    sio.puts <<eom
#{i["subject"]}
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
    sio.puts "= changesets"
    @changesets = []
    i["changesets"].each do |x|
      @changesets << x["revision"]
      sio.puts "== #{x["revision"]} #{x["committed_on"]} #{x["user"]["name"] rescue nil}"
      sio.puts x["comments"]
    end
    sio.puts "= journals"
    i["journals"].each do |x|
      sio.puts "== #{x["user"]["name"]} (#{x["created_on"]})"
      x["details"].each do |y|
        sio.puts JSON(y)
      end
      sio.puts x["notes"]
    end
    more(sio)

  when 's'
    puts backport_command_string

  when /\Adone(?: +(\d+))?(?: -- +(.*))?\z/
    notes = $2
    if $1
      i = issue.to_i
      i = @issues[i]["id"] if @issues && i < @issues.size
      @issue = i
    end

    uri = URI("#{REDMINE_BASE}/issues/#{@issue}.json")
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      res = http.get(uri.path)
      data = JSON(res.body)
      h = data["issue"]["custom_fields"].find{|x|x["id"]==5}
      if h and val = h["value"]
        case val[/(?:\A|, )#{Regexp.quote TARGET_VERSION}: ([^,]+)/, 1]
        when 'REQUIRED', 'UNKNOWN', 'DONTNEED'
          val[*$~.offset(1)] = 'DONE'
        when 'DONE' # , /\A\d+\z/
          puts 'already backport is done'
          next # already done
        when nil
          val << ", #{TARGET_VERSION}: DONE"
        else
          raise "unknown status '#$1'"
        end
      else
        val = '#{TARGET_VERSION}: DONE'
      end

      data = { "issue" => { "custom_fields" => [ {"id"=>5, "value" => val} ] } }
      data['issue']['notes'] = notes if notes
      res = http.put(uri.path, JSON(data),
                     'X-Redmine-API-Key' => REDMINE_API_KEY,
                     'Content-Type' => 'application/json')
      res.value

      show_last_journal(http, uri)
    end
  when /\Aclose(?: +(\d+))?\z/
    if $1
      i = $1.to_i
      i = @issues[i]["id"] if @issues && i < @issues.size
      @issue = i
    end

    uri = URI("#{REDMINE_BASE}/issues/#{@issue}.json")
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      data = { "issue" => { "status_id" => STATUS_CLOSE } }
      res = http.put(uri.path, JSON(data),
                     'X-Redmine-API-Key' => REDMINE_API_KEY,
                     'Content-Type' => 'application/json')
      res.value

      show_last_journal(http, uri)
    end
  when /\last(?: +(\d+))?\z/
    if $1
      i = $1.to_i
      i = @issues[i]["id"] if @issues && i < @issues.size
      @issue = i
    end

    uri = URI("#{REDMINE_BASE}/issues/#{@issue}.json")
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      show_last_journal(http, uri)
    end
  when ''
  when nil, 'quit', 'exit'
    exit
  else
    puts "error #{l.inspect}"
  end
end
