require 'open-uri'
begin
  require 'net/https'
rescue LoadError
  https = 'http'
else
  https = 'https'

  # open-uri of ruby 2.2.0 accept an array of PEMs as ssl_ca_cert, but old
  # versions are not.  so, patching OpenSSL::X509::Store#add_file instead.
  class OpenSSL::X509::Store
    alias orig_add_file add_file
    def add_file(pems)
      Array(pems).each do |pem|
        if File.directory?(pem)
          add_path pem
        else
          orig_add_file pem
        end
      end
    end
  end
  # since open-uri internally checks ssl_ca_cert by File.directory?, to allow
  # accept an array.
  class <<File
    alias orig_directory? directory?
    def File.directory? files
      files.is_a?(Array) ? false : orig_directory?(files)
    end
  end
end

class Downloader
  def self.https
    if @@https != 'https'
      warn "*** using http instead of https ***"
    end
    @@https
  end

  class GNU < self
    def self.download(name, *rest)
      if https == 'https'
        super("https://raw.githubusercontent.com/gcc-mirror/gcc/master/#{name}", name, *rest)
      else
        super("http://repo.or.cz/official-gcc.git/blob_plain/HEAD:/#{name}", name, *rest)
      end
    end
  end

  class RubyGems < self
    def self.download(name, dir = nil, ims = true, options = {})
      require 'rubygems'
      require 'rubygems/package'
      options[:ssl_ca_cert] = Dir.glob(File.expand_path("../lib/rubygems/ssl_certs/*.pem", File.dirname(__FILE__)))
      file = under(dir, name)
      super("#{https}://rubygems.org/downloads/#{name}", file, nil, ims, options) or
        return false
      policy = Gem::Security::LowSecurity
      (policy = policy.dup).ui = Gem::SilentUI.new if policy.respond_to?(:'ui=')
      pkg = Gem::Package.new(file)
      pkg.security_policy = policy
      begin
        pkg.verify
      rescue Gem::Security::Exception => e
        $stderr.puts e.message
        File.unlink(file)
        false
      else
        true
      end
    end

    def self.verify(pkg)
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
    options['Accept-Encoding'] = '*' # to disable Net::HTTP::GenericRequest#decode_content
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
    file = under(dir, name)
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

  def self.under(dir, name)
    dir ? File.join(dir, File.basename(name)) : name
  end
end

Downloader.class_variable_set(:@@https, https.freeze)

if $0 == __FILE__
  ims = true
  until ARGV.empty?
    case ARGV[0]
    when '-d'
      destdir = ARGV[1]
      ARGV.shift
    when '-p'
      # strip directory names from the name to download, and add the
      # prefix instead.
      prefix = ARGV[1]
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
      name = "#{prefix}/#{File.basename(name)}" if prefix
      dl.download(name, destdir, ims)
    end
  else
    abort "usage: #{$0} url name" unless ARGV.size == 2
    Downloader.download(ARGV[0], ARGV[1], destdir, ims)
  end
end
