# Used by configure and make to download or update mirrored Ruby and GCC
# files. This will use HTTPS if possible, falling back to HTTP.

require 'fileutils'
require 'open-uri'
require 'pathname'
begin
  require 'net/https'
rescue LoadError
  https = 'http'
else
  https = 'https'

  # open-uri of ruby 2.2.0 accepts an array of PEMs as ssl_ca_cert, but old
  # versions do not.  so, patching OpenSSL::X509::Store#add_file instead.
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
  # since open-uri internally checks ssl_ca_cert using File.directory?,
  # allow to accept an array.
  class <<File
    alias orig_directory? directory?
    def File.directory? files
      files.is_a?(Array) ? false : orig_directory?(files)
    end
  end
end

class Downloader
  def self.https=(https)
    @@https = https
  end

  def self.https?
    @@https == 'https'
  end

  def self.https
    @@https
  end

  class GNU < self
    def self.download(name, *rest)
      if https?
        super("https://raw.githubusercontent.com/gcc-mirror/gcc/master/#{name}", name, *rest)
      else
        super("https://repo.or.cz/official-gcc.git/blob_plain/HEAD:/#{name}", name, *rest)
      end
    end
  end

  class RubyGems < self
    def self.download(name, dir = nil, since = true, options = {})
      require 'rubygems'
      options = options.dup
      options[:ssl_ca_cert] = Dir.glob(File.expand_path("../lib/rubygems/ssl_certs/**/*.pem", File.dirname(__FILE__)))
      super("https://rubygems.org/downloads/#{name}", name, dir, since, options)
    end
  end

  Gems = RubyGems

  class Unicode < self
    INDEX = {}  # cache index file information across files in the same directory
    UNICODE_PUBLIC = "http://www.unicode.org/Public/"

    def self.download(name, dir = nil, since = true, options = {})
      options = options.dup
      unicode_beta = options.delete(:unicode_beta)
      name_dir_part = name.sub(/[^\/]+$/, '')
      if unicode_beta == 'YES'
        if INDEX.size == 0
          index_options = options.dup
          index_options[:cache_save] = false # TODO: make sure caching really doesn't work for index file
          index_file = super(UNICODE_PUBLIC+name_dir_part, "#{name_dir_part}index.html", dir, true, index_options)
          INDEX[:index] = IO.read index_file
        end
        file_base = File.basename(name, '.txt')
        return if file_base == '.' # Use pre-generated headers and tables
        beta_name = INDEX[:index][/#{Regexp.quote(file_base)}(-[0-9.]+d\d+)?\.txt/]
        # make sure we always check for new versions of files,
        # because they can easily change in the beta period
        super(UNICODE_PUBLIC+name_dir_part+beta_name, name, dir, true, options)
      else
        index_file = Pathname.new(under(dir, name_dir_part+'index.html'))
        if index_file.exist?
          raise "Although Unicode is not in beta, file #{index_file} exists. " +
                "Remove all files in this directory and in .downloaded-cache/ " +
                "because they may be leftovers from the beta period."
        end
        super(UNICODE_PUBLIC+name, name, dir, since, options)
      end
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

  # Downloader.download(url, name, [dir, [since]])
  #
  # Update a file from url if newer version is available.
  # Creates the file if the file doesn't yet exist; however, the
  # directory where the file is being created has to exist already.
  # The +since+ parameter can take the following values, with associated meanings:
  #  true ::
  #    Take the last-modified time of the current file on disk, and only download
  #    if the server has a file that was modified later. Download unconditionally
  #    if we don't have the file yet. Default.
  #  +some time value+ ::
  #    Use this time value instead of the time of modification of the file on disk.
  #  nil ::
  #    Only download the file if it doesn't exist yet.
  #  false ::
  #    always download url regardless of whether we already have a file,
  #    and regardless of modification times. (This is essentially just a waste of
  #    network resources, except in the case that the file we have is somehow damaged.
  #    Please note that using this recurringly might create or be seen as a
  #    denial of service attack.)
  #
  # Example usage:
  #   download 'http://www.unicode.org/Public/UCD/latest/ucd/UnicodeData.txt',
  #            'UnicodeData.txt', 'enc/unicode/data'
  def self.download(url, name, dir = nil, since = true, options = {})
    options = options.dup
    url = URI(url)
    dryrun = options.delete(:dryrun)
    options.delete(:unicode_beta) # just to be on the safe side for gems and gcc

    if name
      file = Pathname.new(under(dir, name))
    else
      name = File.basename(url.path)
    end
    cache_save = options.delete(:cache_save) {
      ENV["CACHE_SAVE"] != "no"
    }
    cache = cache_file(url, name, options.delete(:cache_dir))
    file ||= cache
    if since.nil? and file.exist?
      if $VERBOSE
        $stdout.puts "#{file} already exists"
        $stdout.flush
      end
      if cache_save
        save_cache(cache, file, name)
      end
      return file.to_path
    end
    if dryrun
      puts "Download #{url} into #{file}"
      return
    end
    if link_cache(cache, file, name, $VERBOSE)
      return file.to_path
    end
    if !https? and URI::HTTPS === url
      warn "*** using http instead of https ***"
      url.scheme = 'http'
      url = URI(url.to_s)
    end
    if $VERBOSE
      $stdout.print "downloading #{name} ... "
      $stdout.flush
    end
    begin
      data = with_retry(6) do
        url.read(options.merge(http_options(file, since.nil? ? true : since)))
      end
    rescue OpenURI::HTTPError => http_error
      if http_error.message =~ /^304 / # 304 Not Modified
        if $VERBOSE
          $stdout.puts "#{name} not modified"
          $stdout.flush
        end
        return file.to_path
      end
      raise
    rescue Timeout::Error
      if since.nil? and file.exist?
        puts "Request for #{url} timed out, using old version."
        return file.to_path
      end
      raise
    rescue SocketError
      if since.nil? and file.exist?
        puts "No network connection, unable to download #{url}, using old version."
        return file.to_path
      end
      raise
    end
    mtime = nil
    dest = (cache_save && cache && !cache.exist? ? cache : file)
    dest.parent.mkpath
    dest.open("wb", 0600) do |f|
      f.write(data)
      f.chmod(mode_for(data))
      mtime = data.meta["last-modified"]
    end
    if mtime
      mtime = Time.httpdate(mtime)
      dest.utime(mtime, mtime)
    end
    if $VERBOSE
      $stdout.puts "done"
      $stdout.flush
    end
    if dest.eql?(cache)
      link_cache(cache, file, name)
    elsif cache_save
      save_cache(cache, file, name)
    end
    return file.to_path
  rescue => e
    raise "failed to download #{name}\n#{e.class}: #{e.message}: #{url}"
  end

  def self.under(dir, name)
    dir ? File.join(dir, File.basename(name)) : name
  end

  def self.cache_file(url, name, cache_dir = nil)
    case cache_dir
    when false
      return nil
    when nil
      cache_dir = ENV['CACHE_DIR']
      if !cache_dir or cache_dir.empty?
        cache_dir = ".downloaded-cache"
      end
    end
    Pathname.new(cache_dir) + (name || File.basename(URI(url).path))
  end

  def self.link_cache(cache, file, name, verbose = false)
    return false unless cache and cache.exist?
    return true if cache.eql?(file)
    if /cygwin/ !~ RUBY_PLATFORM or /winsymlink:nativestrict/ =~ ENV['CYGWIN']
      begin
        file.make_symlink(cache.relative_path_from(file.parent))
      rescue SystemCallError
      else
        if verbose
          $stdout.puts "made symlink #{name} to #{cache}"
          $stdout.flush
        end
        return true
      end
    end
    begin
      file.make_link(cache)
    rescue SystemCallError
    else
      if verbose
        $stdout.puts "made link #{name} to #{cache}"
        $stdout.flush
      end
      return true
    end
  end

  def self.save_cache(cache, file, name)
    return unless cache or cache.eql?(file)
    begin
      st = cache.stat
    rescue
      begin
        file.rename(cache)
      rescue
        return
      end
    else
      return unless st.mtime > file.lstat.mtime
      file.unlink
    end
    link_cache(cache, file, name)
  end

  def self.with_retry(max_times, &block)
    times = 0
    begin
      block.call
    rescue Errno::ETIMEDOUT, SocketError, OpenURI::HTTPError, Net::ReadTimeout, Net::OpenTimeout => e
      raise if e.is_a?(OpenURI::HTTPError) && e.message !~ /^50[023] / # retry only 500, 502, 503 for http error
      times += 1
      if times <= max_times
        $stderr.puts "retrying #{e.class} (#{e.message}) after #{times ** 2} seconds..."
        sleep(times ** 2)
        retry
      else
        raise
      end
    end
  end
  private_class_method :with_retry
end

Downloader.https = https.freeze

if $0 == __FILE__
  since = true
  options = {}
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
      since = nil
    when '-a'
      since = false
    when '-n', '--dryrun'
      options[:dryrun] = true
    when '--cache-dir'
      options[:cache_dir] = ARGV[1]
      ARGV.shift
    when '--unicode-beta'
      options[:unicode_beta] = ARGV[1]
      ARGV.shift
    when /\A--cache-dir=(.*)/m
      options[:cache_dir] = $1
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
      dir = destdir
      if prefix
        name = name.sub(/\A\.\//, '')
        destdir2 = destdir.sub(/\A\.\//, '')
        if name.start_with?(destdir2+"/")
          name = name[(destdir2.size+1)..-1]
          if (dir = File.dirname(name)) == '.'
            dir = destdir
          else
            dir = File.join(destdir, dir)
          end
        else
          name = File.basename(name)
        end
        name = "#{prefix}/#{name}"
      end
      dl.download(name, dir, since, options)
    end
  else
    abort "usage: #{$0} url name" unless ARGV.size == 2
    Downloader.download(ARGV[0], ARGV[1], destdir, since, options)
  end
end
