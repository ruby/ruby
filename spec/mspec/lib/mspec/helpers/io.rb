require 'mspec/guards/feature'

class IOStub
  def initialize
    @buffer = []
    @output = ''
  end

  def write(*str)
    self << str.join
  end

  def << str
    @buffer << str
    self
  end

  def print(*str)
    write(str.join + $\.to_s)
  end

  def method_missing(name, *args, &block)
    to_s.send(name, *args, &block)
  end

  def == other
    to_s == other
  end

  def =~ other
    to_s =~ other
  end

  def puts(*str)
    if str.empty?
      write "\n"
    else
      write(str.collect { |s| s.to_s.chomp }.concat([nil]).join("\n"))
    end
  end

  def printf(format, *args)
    self << sprintf(format, *args)
  end

  def flush
    @output += @buffer.join('')
    @buffer.clear
    self
  end

  def to_s
    flush
    @output
  end

  alias_method :to_str, :to_s

  def inspect
    to_s.inspect
  end
end

# Creates a "bare" file descriptor (i.e. one that is not associated
# with any Ruby object). The file descriptor can safely be passed
# to IO.new without creating a Ruby object alias to the fd.
def new_fd(name, mode="w:utf-8")
  mode = options_or_mode(mode)

  if mode.kind_of? Hash
    if mode.key? :mode
      mode = mode[:mode]
    else
      raise ArgumentError, "new_fd options Hash must include :mode"
    end
  end

  IO.sysopen name, fmode(mode)
end

# Creates an IO instance for a temporary file name. The file
# must be deleted.
def new_io(name, mode="w:utf-8")
  IO.new new_fd(name, options_or_mode(mode)), options_or_mode(mode)
end

# This helper simplifies passing file access modes regardless of
# whether the :encoding feature is enabled. Only the access specifier
# itself will be returned if :encoding is not enabled. Otherwise,
# the full mode string will be returned (i.e. the helper is a no-op).
def fmode(mode)
  if FeatureGuard.enabled? :encoding
    mode
  else
    mode.split(':').first
  end
end

# This helper simplifies passing file access modes or options regardless of
# whether the :encoding feature is enabled. Only the access specifier itself
# will be returned if :encoding is not enabled. Otherwise, the full mode
# string or option will be returned (i.e. the helper is a no-op).
def options_or_mode(oom)
  return fmode(oom) if oom.kind_of? String

  if FeatureGuard.enabled? :encoding
    oom
  else
    fmode(oom[:mode] || "r:utf-8")
  end
end
