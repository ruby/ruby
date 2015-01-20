require 'open-uri'

class Downloader
  class GNU < self
    def self.download(name, *rest)
      super("http://gcc.gnu.org/git/?p=gcc.git;a=blob_plain;f=#{name};hb=master", name, *rest)
    end
  end

  class RubyGems < self
    def self.download(name, dir = nil, ims = true, options = {})
      options[:ssl_ca_cert] = Dir.glob(File.expand_path("../lib/rubygems/ssl_certs/*.pem", File.dirname(__FILE__)))
      super("https://rubygems.org/downloads/#{name}", name, dir, ims, options)
    end
  end

  Gems = RubyGems

  class Unicode < self
    def self.download(name, *rest)
      super("http://www.unicode.org/Public/#{name}", name, *rest)
    end
  end

  def self.mode_for(data)
    /\A#!/ =~ data ? 0755 : 0644
  end

  def self.http_options(file, since)
    options = {}
    if since
      case since
      when true
        since = (File.mtime(file).httpdate rescue nil)
      when Time
        since = since.httpdate
      end
      if since
        options['If-Modified-Since'] = since
      end
    end
    options
  end

  # Downloader.download(url, name, [dir, [ims]])
  #
  # Update a file from url if newer version is available.
  # Creates the file if the file doesn't yet exist; however, the
  # directory where the file is being created has to exist already.
  # If +ims+ is false, always download url regardless of its last
  # modified time.
  #
  # Example usage:
  #   download 'http://www.unicode.org/Public/UCD/latest/ucd/UnicodeData.txt',
  #            'UnicodeData.txt', 'enc/unicode/data'
  def self.download(url, name, dir = nil, ims = true, options = {})
    file = dir ? File.join(dir, File.basename(name)) : name
    if ims.nil? and File.exist?(file)
      if $VERBOSE
        $stdout.puts "#{name} already exists"
        $stdout.flush
      end
      return true
    end
    url = URI(url)
    if $VERBOSE
      $stdout.print "downloading #{name} ... "
      $stdout.flush
    end
    begin
      data = url.read(options.merge(http_options(file, ims.nil? ? true : ims)))
    rescue OpenURI::HTTPError => http_error
      if http_error.message =~ /^304 / # 304 Not Modified
        if $VERBOSE
          $stdout.puts "not modified"
          $stdout.flush
        end
        return true
      end
      raise
    rescue Timeout::Error
      if ims.nil? and File.exist?(file)
        puts "Request for #{url} timed out, using old version."
        return true
      end
      raise
    rescue SocketError
      if ims.nil? and File.exist?(file)
        puts "No network connection, unable to download #{url}, using old version."
        return true
      end
      raise
    end
    mtime = nil
    open(file, "wb", 0600) do |f|
      f.write(data)
      f.chmod(mode_for(data))
      mtime = data.meta["last-modified"]
    end
    if mtime
      mtime = Time.httpdate(mtime)
      File.utime(mtime, mtime, file)
    end
    if $VERBOSE
      $stdout.puts "done"
      $stdout.flush
    end
    true
  rescue => e
    raise "failed to download #{name}\n#{e.message}: #{url}"
  end
end

if $0 == __FILE__
  ims = true
  until ARGV.empty?
    case ARGV[0]
    when '-d'
      destdir = ARGV[1]
      ARGV.shift
    when '-e'
      ims = nil
    when '-a'
      ims = true
    when /\A-/
      abort "#{$0}: unknown option #{ARGV[0]}"
    else
      break
    end
    ARGV.shift
  end
  dl = Downloader.constants.find do |name|
    ARGV[0].casecmp(name.to_s) == 0
  end unless ARGV.empty?
  $VERBOSE = true
  if dl
    dl = Downloader.const_get(dl)
    ARGV.shift
    ARGV.each do |name|
      dl.download(name, destdir, ims)
    end
  else
    abort "usage: #{$0} url name" unless ARGV.size == 2
    Downloader.download(ARGV[0], ARGV[1], destdir, ims)
  end
end
