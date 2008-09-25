require 'tempfile'
require 'rubygems'
require 'rubygems/remote_fetcher'

##
# A fake Gem::RemoteFetcher for use in tests or to avoid real live HTTP
# requests when testing code that uses RubyGems.
#
# Example:
#
#   @fetcher = Gem::FakeFetcher.new
#   @fetcher.data['http://gems.example.com/yaml'] = source_index.to_yaml
#   Gem::RemoteFetcher.fetcher = @fetcher
#   
#   # invoke RubyGems code
#   
#   paths = @fetcher.paths
#   assert_equal 'http://gems.example.com/yaml', paths.shift
#   assert paths.empty?, paths.join(', ')
#
# See RubyGems' tests for more examples of FakeFetcher.

class Gem::FakeFetcher

  attr_reader :data
  attr_accessor :paths

  def initialize
    @data = {}
    @paths = []
  end

  def fetch_path path, mtime = nil
    path = path.to_s
    @paths << path
    raise ArgumentError, 'need full URI' unless path =~ %r'^http://'

    unless @data.key? path then
      raise Gem::RemoteFetcher::FetchError.new("no data for #{path}", path)
    end

    data = @data[path]

    if data.respond_to?(:call) then
      data.call
    else
      if path.to_s =~ /gz$/ and not data.nil? and not data.empty? then
        data = Gem.gunzip data
      end

      data
    end
  end

  def fetch_size(path)
    path = path.to_s
    @paths << path

    raise ArgumentError, 'need full URI' unless path =~ %r'^http://'

    unless @data.key? path then
      raise Gem::RemoteFetcher::FetchError.new("no data for #{path}", path)
    end

    data = @data[path]

    data.respond_to?(:call) ? data.call : data.length
  end

  def download spec, source_uri, install_dir = Gem.dir
    name = "#{spec.full_name}.gem"
    path = File.join(install_dir, 'cache', name)

    Gem.ensure_gem_subdirectories install_dir

    if source_uri =~ /^http/ then
      File.open(path, "wb") do |f|
        f.write fetch_path(File.join(source_uri, "gems", name))
      end
    else
      FileUtils.cp source_uri, path
    end

    path
  end

end

# :stopdoc:
class Gem::RemoteFetcher

  def self.fetcher=(fetcher)
    @fetcher = fetcher
  end

end
# :startdoc:

##
# A StringIO duck-typed class that uses Tempfile instead of String as the
# backing store.
#--
# This class was added to flush out problems in Rubinius' IO implementation.

class TempIO

  @@count = 0

  def initialize(string = '')
    @tempfile = Tempfile.new "TempIO-#{@@count += 1}"
    @tempfile.binmode
    @tempfile.write string
    @tempfile.rewind
  end

  def method_missing(meth, *args, &block)
    @tempfile.send(meth, *args, &block)
  end

  def respond_to?(meth)
    @tempfile.respond_to? meth
  end

  def string
    @tempfile.flush

    Gem.read_binary @tempfile.path
  end

end

