require 'open-uri'

class Downloader
  class GNU < self
    def self.download(name, *rest)
      super("http://git.savannah.gnu.org/gitweb/?p=config.git;a=blob_plain;f=#{name};hb=HEAD", name, *rest)
    end
  end

  class RubyGems < self
    def self.download(name, *rest)
      super("https://rubygems.org/downloads/#{name}", name, *rest)
    end
  end

  Gems = RubyGems

  class Unicode < self
    def self.download(name, *rest)
      super("http://www.unicode.org/Public/UCD/latest/ucd/#{name}", name, *rest)
    end
  end

  def self.mode_for(data)
    data.start_with?("#!") ? 0755 : 0644
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
  #   download :unicode, 'UnicodeData.txt', 'enc/unicode/data'
  def self.download(url, name, dir = nil, ims = true)
    file = dir ? File.join(dir, name) : name
    url = URI(url)
    if $VERBOSE
      $stdout.print "downloading #{name} ... "
      $stdout.flush
    end
    begin
      data = url.read(http_options(file, ims))
    rescue OpenURI::HTTPError => http_error
      if http_error.message =~ /^304 / # 304 Not Modified
        if $VERBOSE
          $stdout.puts "not modified"
          $stdout.flush
        end
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
    raise e.class, "failed to download #{name}\n#{e.message}: #{url}", e.backtrace
  end
end
