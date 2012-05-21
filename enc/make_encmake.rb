#! ./miniruby

dir = File.expand_path("../..", __FILE__)
$:.unshift(dir)
$:.unshift(".")
if $".grep(/mkmf/).empty?
  $" << "mkmf.rb"
  load File.expand_path("lib/mkmf.rb", dir)
end
require 'erb'

CONFIG["MAKEDIRS"] ||= '$(MINIRUBY) -run -e mkdir -- -p'

BUILTIN_ENCS = []
BUILTIN_TRANSES = []
ENC_PATTERNS = []
NOENC_PATTERNS = []
module_type = :dynamic

until ARGV.empty?
  case ARGV[0]
  when /\A--builtin-encs=/
    BUILTIN_ENCS.concat $'.split.map {|e| File.basename(e, '.*') << '.c'}
    ARGV.shift
  when /\A--builtin-transes=/
    BUILTIN_TRANSES.concat $'.split.map {|e| File.basename(e, '.*') }
    ARGV.shift
  when /\A--encs=/
    ENC_PATTERNS.concat $'.split
    ARGV.shift
  when /\A--no-encs=/
    NOENC_PATTERNS.concat $'.split
    ARGV.shift
  when /\A--module$/
    ARGV.shift
  when /\A--modulestatic$/
    module_type = :static
    ARGV.shift
  else
    break
  end
end

ALPHANUMERIC_ORDER = proc {|e| e.scan(/(\d+)|(\D+)/).map {|n,a| a||[n.size,n.to_i]}.flatten}
def target_encodings
  encs = Dir.open($srcdir) {|d| d.grep(/.+\.c\z/)} - BUILTIN_ENCS - ["mktable.c"]
  encs.each {|e| e.chomp!(".c")}
  encs.reject! {|e| !ENC_PATTERNS.any? {|p| File.fnmatch?(p, e)}} if !ENC_PATTERNS.empty?
  encs.reject! {|e| NOENC_PATTERNS.any? {|p| File.fnmatch?(p, e)}}
  encs = encs.sort_by(&ALPHANUMERIC_ORDER)
  deps = Hash.new {[]}
  inc_srcs = Hash.new {[]}
  default_deps = %w[regenc.h oniguruma.h config.h defines.h]
  db = encs.delete("encdb")
  encs.each do |e|
    File.foreach("#$srcdir/#{e}.c") do |l|
      if /^\s*#\s*include\s+(?:"([^\"]+)"|<(ruby\/\sw+.h)>)/ =~ l
        n = $1 || $2
        if /\.c$/ =~ n
          inc_srcs[e] <<= $`
          n = "enc/#{n}"
        end
        deps[e] <<= n unless default_deps.include?(n)
      end
    end
  end
  class << inc_srcs; self; end.class_eval do
    define_method(:expand) do |d|
      d.map {|n| deps[n] | self.expand(self[n])}.flatten
    end
  end
  inc_srcs.each do |e, d|
    deps[e].concat(inc_srcs.expand(d))
  end
  encs.unshift(db)
  return encs, deps
end

def target_transcoders
  atrans = []
  trans = Dir.open($srcdir+"/trans") {|d|
    d.select {|e|
      if e.chomp!('.trans')
        atrans << e
        true
      elsif e.chomp!('.c')
        true
      end
    }
  }
  trans -= BUILTIN_TRANSES
  atrans -= BUILTIN_TRANSES
  trans.uniq!
  atrans = atrans.sort_by(&ALPHANUMERIC_ORDER)
  trans = trans.sort_by(&ALPHANUMERIC_ORDER)
  trans.unshift(trans.delete("transdb"))
  trans.compact!
  trans |= atrans
  trans.map! {|e| "trans/#{e}"}

  return atrans, trans
end

# Constants that "depend" needs.
MODULE_TYPE = module_type
ENCS, ENC_DEPS = target_encodings
ATRANS, TRANS = target_transcoders

if File.exist?(depend = File.join($srcdir, "depend"))
  erb = ERB.new(File.read(depend), nil, '%')
  erb.filename = depend
  tmp = erb.result(binding)
  dep = "\n#### depend ####\n\n" << depend_rules(tmp).join
else
  dep = ""
end
mkin = File.read(File.join($srcdir, "Makefile.in"))
mkin.gsub!(/@(#{CONFIG.keys.join('|')})@/) {CONFIG[$1]}
open(ARGV[0], 'wb') {|f|
  f.puts mkin, dep
}
if MODULE_TYPE == :static
  erb = ERB.new(File.read(File.join($srcdir, "encinit.c.erb")), nil, '%-')
  erb.filename = "enc/encinit.c.cerb"
  tmp = erb.result(binding)
  begin
    Dir.mkdir 'enc'
  rescue Errno::EEXIST
  end
  File.open("enc/encinit.c", "w") {|f|
    f.puts "/* Automatically generated from enc/encinit.c.erb"
    f.puts " * Do not edit."
    f.puts " */"
    f.puts tmp
  }
end
