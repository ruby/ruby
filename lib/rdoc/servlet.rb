require 'rdoc'
require 'time'
require 'webrick'

class RDoc::Servlet < WEBrick::HTTPServlet::AbstractServlet

  @server_stores = Hash.new { |hash, server| hash[server] = {} }
  @cache         = Hash.new { |hash, store|  hash[store]  = {} }

  attr_reader :asset_dirs

  attr_reader :options

  def self.get_instance server, *options
    stores = @server_stores[server]

    new server, stores, @cache, *options
  end

  def initialize server, stores, cache, mount_path = nil
    super server

    @cache      = cache
    @mount_path = mount_path
    @stores     = stores

    @options = RDoc::Options.new
    @options.op_dir = '.'

    darkfish_dir = nil

    # HACK dup
    $LOAD_PATH.each do |path|
      darkfish_dir = File.join path, 'rdoc/generator/template/darkfish/'
      next unless File.directory? darkfish_dir
      @options.template_dir = darkfish_dir
      break
    end

    @asset_dirs = {
      :darkfish   => darkfish_dir,
      :json_index =>
        File.expand_path('../generator/template/json_index/', __FILE__),
    }
  end

  def asset generator_name, req, res
    asset_dir = @asset_dirs[generator_name]

    asset_path = File.join asset_dir, req.path

    if_modified_since req, res, asset_path

    res.body = File.read asset_path

    res.content_type = case req.path
                       when /css$/ then 'text/css'
                       when /js$/  then 'application/javascript'
                       else             'application/octet-stream'
                       end
  end

  def do_GET req, res
    req.path.sub!(/^#{Regexp.escape @mount_path}/o, '') if @mount_path

    case req.path
    when '/' then
      root req, res
    when '/rdoc.css', '/js/darkfish.js', '/js/jquery.js', '/js/search.js',
         %r%^/images/% then
      asset :darkfish, req, res
    when '/js/navigation.js', '/js/searcher.js' then
      asset :json_index, req, res
    when '/js/search_index.js' then
      root_search req, res
    else
      show_documentation req, res
    end
  rescue WEBrick::HTTPStatus::Status
    raise
  rescue => e
    error e, req, res
  end

  def documentation_page store, generator, path, req, res
    name = path.sub(/.html$/, '').gsub '/', '::'

    if klass = store.find_class_or_module(name) then
      res.body = generator.generate_class klass
    elsif page = store.find_text_page(name.sub(/_([^_]*)$/, '.\1')) then
      res.body = generator.generate_page page
    else
      not_found generator, req, res
    end
  end

  def documentation_search store, generator, req, res
    json_index = @cache[store].fetch :json_index do
      @cache[store][:json_index] =
        JSON.dump generator.json_index.build_index
    end

    res.content_type = 'application/javascript'
    res.body = "var search_data = #{json_index}"
  end

  def documentation_source path
    _, source_name, path = path.split '/', 3

    store = @stores[source_name]
    return store, path if store

    store = store_for source_name

    store.load_all

    @stores[source_name] = store

    return store, path
  end

  def error e, req, res
    backtrace = e.backtrace.join "\n"

    res.content_type = 'text/html'
    res.status = 500
    res.body = <<-BODY
<!DOCTYPE html>
<html>
<head>
<meta content="text/html; charset=UTF-8" http-equiv="Content-Type">

<title>Error - #{ERB::Util.html_escape e.class}</title>

<link type="text/css" media="screen" href="#{@mount_path}/rdoc.css" rel="stylesheet">
</head>
<body>
<h1>Error</h1>

<p>While processing <code>#{ERB::Util.html_escape req.request_uri}</code> the
RDoc server has encountered a <code>#{ERB::Util.html_escape e.class}</code>
exception:

<pre>#{ERB::Util.html_escape e.message}</pre>

<p>Backtrace:

<pre>#{ERB::Util.html_escape backtrace}</pre>

</body>
</html>
    BODY
  end

  def generator_for store
    generator = RDoc::Generator::Darkfish.new store, @options
    generator.file_output = false
    generator.asset_rel_path = '..'

    rdoc = RDoc::RDoc.new
    rdoc.store     = store
    rdoc.generator = generator
    rdoc.options   = @options

    @options.main_page = store.main
    @options.title     = store.title

    generator
  end

  def if_modified_since req, res, path = nil
    last_modified = File.stat(path).mtime if path

    res['last-modified'] = last_modified.httpdate

    return unless ims = req['if-modified-since']

    ims = Time.parse ims

    unless ims < last_modified then
      res.body = ''
      raise WEBrick::HTTPStatus::NotModified
    end
  end

  def installed_docs
    ri_paths.map do |path, type|
      store = RDoc::Store.new path, type
      exists = File.exist? store.cache_path

      case type
      when :gem then
        gem_path = path[%r%/([^/]*)/ri$%, 1]
        [gem_path, "#{gem_path}/", exists, type, path]
      when :system then
        ['Ruby Documentation', 'ruby/', exists, type, path]
      when :site then
        ['Site Documentation', 'site/', exists, type, path]
      when :home then
        ['Home Documentation', 'home/', exists, type, path]
      end
    end
  end

  def not_found generator, req, res
    res.body = generator.generate_servlet_not_found req.path
    res.status = 404
  end

  def ri_paths &block
    RDoc::RI::Paths.each true, true, true, :all, &block
  end

  def root req, res
    generator = RDoc::Generator::Darkfish.new nil, @options

    res.body = generator.generate_servlet_root installed_docs

    res.content_type = 'text/html'
  end

  def root_search req, res
    search_index = []
    info         = []

    installed_docs.map do |name, href, exists, type, path|
      next unless exists

      search_index << name

      comment = case type
                when :gem
                  gemspec = path.gsub(%r%/doc/([^/]*?)/ri$%,
                                      '/specifications/\1.gemspec')

                  spec = Gem::Specification.load gemspec

                  spec.summary
                when :system then
                  'Documentation for the Ruby standard library'
                when :site then
                  'Documentation for non-gem libraries'
                when :home then
                  'Documentation from your home directory'
                end

      info << [name, '', path, '', comment]
    end

    index = {
      :index => {
        :searchIndex     => search_index,
        :longSearchIndex => search_index,
        :info            => info,
      }
    }

    res.body = "var search_data = #{JSON.dump index};"
    res.content_type = 'application/javascript'
  end

  def show_documentation req, res
    store, path = documentation_source req.path

    if_modified_since req, res, store.cache_path

    generator = generator_for store

    case path
    when nil, '', 'index.html' then
      res.body = generator.generate_index
    when 'table_of_contents.html' then
      res.body = generator.generate_table_of_contents
    when 'js/search_index.js' then
      documentation_search store, generator, req, res
    else
      documentation_page store, generator, path, req, res
    end
  ensure
    res.content_type ||= 'text/html'
  end

  def store_for source_name
    case source_name
    when 'ruby' then
      RDoc::Store.new RDoc::RI::Paths.system_dir, :system
    else
      ri_dir, type = ri_paths.find do |dir, dir_type|
        next unless dir_type == :gem

        source_name == dir[%r%/([^/]*)/ri$%, 1]
      end

      raise "could not find ri documentation for #{source_name}" unless
        ri_dir

      RDoc::Store.new ri_dir, type
    end
  end

end

