#!./miniruby -ps

BEGIN {
  CONFIG = {}

  RUBY_VERSION.scan(/(\d+)\.(\d+)\.(\d+)/) do
    # overridden if config.status has version
    CONFIG['MAJOR'] = $1
    CONFIG['MINOR'] = $2
    CONFIG['TEENY'] = $3
  end

  File.foreach($config || "config.status") do |$_|
    next if /^#/
    if /^s%@(\w+)@%(.*)%g/
      name = $1
      val = $2 || ""
      next if /^(INSTALL|DEFS|configure_input|srcdir)$/ =~ name
      val.gsub!(/\$\{([^{}]+)\}/) { "$(#{$1})" }
      CONFIG[name] = val
    end
  end

  CONFIG['top_srcdir'] = File.expand_path($srcdir || ".")
  CONFIG['RUBY_INSTALL_NAME'] = $install_name if $install_name
  CONFIG['RUBY_SO_NAME'] = $so_name if $so_name
  $defout = open($output, 'w') if $output
}

gsub!(/@(\w+)@/) {CONFIG[$1] || $&}

# vi:set sw=2:
