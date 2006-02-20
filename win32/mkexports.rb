#!./miniruby -s

module RbConfig
  autoload :CONFIG, "rbconfig"
end

class Exports
  @subclass = []
  def self.inherited(klass)
    @subclass << [/#{klass.name.sub(/.*::/, '').downcase}/i, klass]
  end

  def self.create(*args, &block)
    platform = RUBY_PLATFORM
    pat, klass = @subclass.find {|pat, klass| pat =~ platform}
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
      open(output, 'w', &block)
    else
      yield STDOUT
    end
  end

  def initialize(objs)
    syms = {}
    winapis = {}
    internal = export = nil
    each_export(objs) do |internal, export|
      syms[internal] = export
      winapis[$1] = internal if /^_?(rb_w32_\w+)(?:@\d+)?$/ =~ internal
    end
    win32h = File.join(File.dirname(__FILE__), "win32.h")
    IO.foreach(win32h) do |line|
      if /^#define (\w+)\((.*?)\)\s+(?:\(void\))?(rb_w32_\w+)\((.*?)\)\s*$/ =~ line and
          $2.delete(" ") == $4.delete(" ")
        export, internal = $1, $3
        if syms[internal] or internal = winapis[internal]
          syms[forwarding(internal, export)] = internal
        end
      end
    end
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
    k = v = nil
    exports << "EXPORTS" << symbols()
    exports
  end

  private
  def forwarding(internal, export)
    internal.sub(/^[^@]+/, "\\1#{export}")
  end

  def each_export(objs)
  end

  def symbols()
    @syms.sort.collect {|k, v| v ? "#{k}=#{v}" : k}
  end
end

class Exports::Mswin < Exports
  def each_export(objs)
    noprefix = ($arch and /^sh/ !~ $arch)
    objs = objs.collect {|s| s.tr('/', '\\')}
    filetype = nil
    IO.popen(%w"dumpbin -symbols -exports" + objs) do |f|
      f.each do |l|
        if (filetype = l[/^File Type: (.+)/, 1])..(/^\f/ =~ l)
          case filetype
          when /OBJECT/, /LIBRARY/
            next if /^[[:xdigit:]]+ 0+ UNDEF / =~ l
            next unless l.sub!(/.*\sExternal\s+\|\s+/, '')
            if noprefix or l.sub!(/^_/, '')
              next if /@.*@/ =~ l || /@[[:xdigit:]]{16}$/ =~ l
              l.sub!(/^/, '_') if /@\d+$/ =~ l
            elsif !l.sub!(/^(\S+) \([^@?\`\']*\)$/, '\1')
              next
            end
          when /DLL/
            next unless l.sub!(/^\s*\d+\s+[[:xdigit:]]+\s+[[:xdigit:]]+\s+/, '')
          else
            next
          end
          yield l.strip
        end
      end
    end
    yield "strcasecmp", "msvcrt.stricmp"
    yield "strncasecmp", "msvcrt.strnicmp"
  end
end

class Exports::Mingw < Exports
  def self.nm
    @@nm ||= RbConfig::CONFIG["NM"]
  end

  def each_export(objs)
    IO.popen([self.class.nm, "--extern", "--defined", *objs]) do |f|
      f.each {|l| yield $1 if / [[:upper:]] _(.*)$/ =~ l}
    end
    yield "strcasecmp", "_stricmp"
    yield "strncasecmp", "_strnicmp"
  end

  def symbols()
    @syms.select {|k, v| v}.sort.collect {|k, v| "#{k}=#{v}"}
  end
end

END {
  exports = Exports.extract(ARGV)
  Exports.output {|f| f.puts exports}
}
