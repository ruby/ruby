#!./miniruby -sI.

$name = $library = $description = nil

module RbConfig
  autoload :CONFIG, "rbconfig"
end

class Exports
  @@subclass = []
  def self.inherited(klass)
    @@subclass << [/#{klass.name.sub(/.*::/, '').downcase}/i, klass]
  end

  def self.create(*args, &block)
    platform = RUBY_PLATFORM
    pat, klass = @@subclass.find {|p, k| p =~ platform}
    unless klass
      raise ArgumentError, "unsupported platform: #{platform}"
    end
    klass.new(*args, &block)
  end

  def self.extract(objs, *rest)
    create(objs).exports(*rest)
  end

  def self.output(output = $output, &block)
    if output
      open(output, 'wb', &block)
    else
      yield STDOUT
    end
  end

  def initialize(objs)
    syms = {}
    winapis = {}
    each_export(objs) do |internal, export|
      syms[internal] = export
      winapis[$1] = internal if /^_?(rb_w32_\w+)(?:@\d+)?$/ =~ internal
    end
    win32h = File.join(File.dirname(File.dirname(__FILE__)), "include/ruby/win32.h")
    IO.foreach(win32h) do |line|
      if /^#define (\w+)\((.*?)\)\s+(?:\(void\))?(rb_w32_\w+)\((.*?)\)\s*$/ =~ line and
          $2.delete(" ") == $4.delete(" ")
        export, internal = $1, $3
        if syms[internal] or internal = winapis[internal]
          syms[forwarding(internal, export)] = internal
        end
      end
    end
    syms["NtInitialize"] ||= "ruby_sysinit" if syms["ruby_sysinit"]
    syms["rb_w32_vsnprintf"] ||= "vsnprintf"
    syms["rb_w32_snprintf"] ||= "snprintf"
    @syms = syms
  end

  def exports(name = $name, library = $library, description = $description)
    exports = []
    if name
      exports << "Name " + name
    elsif library
      exports << "Library " + library
    end
    exports << "Description " + description.dump if description
    exports << "VERSION #{RbConfig::CONFIG['MAJOR']}.#{RbConfig::CONFIG['MINOR']}"
    exports << "EXPORTS" << symbols()
    exports
  end

  private
  def forwarding(internal, export)
    internal.sub(/^[^@]+/, "\\1#{export}")
  end

  def each_export(objs)
  end

  def objdump(objs, &block)
    if objs.empty?
      $stdin.each_line(&block)
    else
      each_line(objs, &block)
    end
  end

  def symbols()
    @syms.sort.collect {|k, v| v ? v == true ? "#{k} DATA" : "#{k}=#{v}" : k}
  end
end

class Exports::Mswin < Exports
  def each_line(objs, &block)
    IO.popen(%w"dumpbin -symbols -exports" + objs) do |f|
      f.each(&block)
    end
  end

  def each_export(objs)
    noprefix = ($arch ||= nil and /^(sh|i\d86)/ !~ $arch)
    objs = objs.collect {|s| s.tr('/', '\\')}
    filetype = nil
    objdump(objs) do |l|
      if (filetype = l[/^File Type: (.+)/, 1])..(/^\f/ =~ l)
        case filetype
        when /OBJECT/, /LIBRARY/
          next if /^[[:xdigit:]]+ 0+ UNDEF / =~ l
          next unless /External/ =~ l
          next unless l.sub!(/.*?\s(\(\)\s+)?External\s+\|\s+/, '')
          is_data = !$1
          if noprefix or /^[@_]/ =~ l
            next if /(?!^)@.*@/ =~ l || /@[[:xdigit:]]{16}$/ =~ l || /^_DllMain@/ =~ l
            l.sub!(/^[@_]/, '') if /@\d+$/ !~ l
          elsif !l.sub!(/^(\S+) \([^@?\`\']*\)$/, '\1')
            next
          end
        when /DLL/
          next unless l.sub!(/^\s*\d+\s+[[:xdigit:]]+\s+[[:xdigit:]]+\s+/, '')
        else
          next
        end
        yield l.strip, is_data
      end
    end
    yield "strcasecmp", "msvcrt.stricmp"
    yield "strncasecmp", "msvcrt.strnicmp"
  end
end

class Exports::Cygwin < Exports
  def self.nm
    @@nm ||= RbConfig::CONFIG["NM"]
  end

  def exports(*)
    super()
  end

  def each_line(objs, &block)
    IO.foreach("|#{self.class.nm} --extern --defined #{objs.join(' ')}", &block)
  end

  def each_export(objs)
    objdump(objs) do |l|
      next if /@.*@/ =~ l
      yield $2, !$1 if /\s(?:(T)|[[:upper:]])\s_((?!Init_|.*_threadptr_|DllMain@).*)$/ =~ l
    end
  end
end

class Exports::Mingw < Exports::Cygwin
  def each_export(objs)
    super
    yield "strcasecmp", "_stricmp"
    yield "strncasecmp", "_strnicmp"
  end
end

END {
  exports = Exports.extract(ARGV)
  Exports.output {|f| f.puts(*exports)}
}
