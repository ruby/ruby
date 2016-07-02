#!./miniruby -s

# Used to expand Ruby config entries for Win32 Makefiles.

config = File.read(conffile = $config)
config.sub!(/^(\s*)RUBY_VERSION\b.*(\sor\s*)$/, '\1true\2')
rbconfig = Module.new {module_eval(config, conffile)}::RbConfig
config = $expand ? rbconfig::CONFIG : rbconfig::MAKEFILE_CONFIG
config["RUBY_RELEASE_DATE"] ||=
  File.read(File.expand_path("../../version.h", __FILE__))[/^\s*#\s*define\s+RUBY_RELEASE_DATE\s+"(.*)"/, 1]

while /\A(\w+)=(.*)/ =~ ARGV[0]
  config[$1] = $2
  config[$1].tr!(File::ALT_SEPARATOR, File::SEPARATOR) if File::ALT_SEPARATOR
  ARGV.shift
end

re = /@(#{config.keys.map {|k| Regexp.quote(k)}.join('|')})@/

if $output
  output = open($output, "wb", $mode &&= $mode.oct)
  output.chmod($mode) if $mode
else
  output = STDOUT
  output.binmode
end

ARGF.each do |line|
  line.gsub!(/@([a-z_]\w*)@/i) {
    s = config.fetch($1, $expand ? $& : "")
    s = s.gsub(/\$\((.+?)\)/, %Q[${\\1}]) unless $expand
    s
  }
  output.puts line
end
