#!./miniruby -s

# Used to expand Ruby config entries for Win32 Makefiles.

config = File.read(conffile = $config)
config.sub!(/^(\s*)RUBY_VERSION\b.*(\sor\s*)$/, '\1true\2')
rbconfig = Module.new {module_eval(config, conffile)}::RbConfig
config = $expand ? rbconfig::CONFIG : rbconfig::MAKEFILE_CONFIG
config["RUBY_RELEASE_DATE"] ||=
  [
    ["revision.h"],
    ["../../revision.h", __FILE__],
    ["../../version.h", __FILE__],
  ].find do |hdr, dir|
  hdr = File.expand_path(hdr, dir) if dir
  if date = File.read(hdr)[/^\s*#\s*define\s+RUBY_RELEASE_DATE(?:TIME)?\s+"([0-9-]*)/, 1]
    break date
  end
rescue
end

while /\A(\w+)=(.*)/ =~ ARGV[0]
  config[$1] = $2
  config[$1].tr!(File::ALT_SEPARATOR, File::SEPARATOR) if File::ALT_SEPARATOR
  ARGV.shift
end

if $output
  output = File.open($output, "wb", $mode &&= $mode.oct)
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
