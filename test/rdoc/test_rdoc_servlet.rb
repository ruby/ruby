# frozen_string_literal: true
require_relative 'helper'

class TestRDocServlet < RDoc::TestCase

  def setup
    super

    @orig_gem_path = Gem.path

    @tempdir = File.join Dir.tmpdir, "test_rdoc_servlet_#{$$}"
    Gem.use_paths @tempdir
    Gem.ensure_gem_subdirectories @tempdir

    @spec = Gem::Specification.new 'spec', '1.0'
    @spec.loaded_from = @spec.spec_file

    Gem::Specification.reset
    Gem::Specification.all = [@spec]

    @server = {}
    def @server.mount(*) end

    @stores = {}
    @cache  = Hash.new { |hash, store| hash[store] = {} }

    @extra_dirs = [File.join(@tempdir, 'extra1'), File.join(@tempdir, 'extra2')]

    @s = RDoc::Servlet.new @server, @stores, @cache, nil, @extra_dirs

    @req = WEBrick::HTTPRequest.new :Logger => nil
    @res = WEBrick::HTTPResponse.new :HTTPVersion => '1.0'

    def @req.path= path
      instance_variable_set :@path, path
    end

    @req.instance_variable_set :@header, Hash.new { |h, k| h[k] = [] }

    @base        = File.join @tempdir, 'base'
    @system_dir  = File.join @tempdir, 'base', 'system'
    @home_dir    = File.join @tempdir, 'home'
    @gem_doc_dir = File.join @tempdir, 'doc'

    @orig_base = RDoc::RI::Paths::BASE
    RDoc::RI::Paths::BASE.replace @base
    @orig_ri_path_homedir = RDoc::RI::Paths::HOMEDIR
    RDoc::RI::Paths::HOMEDIR.replace @home_dir

    RDoc::RI::Paths.instance_variable_set \
      :@gemdirs, %w[/nonexistent/gems/example-1.0/ri]
  end

  def teardown
    super

    Gem.use_paths(*@orig_gem_path)
    Gem::Specification.reset

    FileUtils.rm_rf @tempdir

    RDoc::RI::Paths::BASE.replace @orig_base
    RDoc::RI::Paths::HOMEDIR.replace @orig_ri_path_homedir
    RDoc::RI::Paths.instance_variable_set :@gemdirs, nil
  end

  def test_asset
    temp_dir do
      FileUtils.mkdir 'css'

      now = Time.now
      File.open 'css/rdoc.css', 'w' do |io| io.write 'h1 { color: red }' end
      File.utime now, now, 'css/rdoc.css'

      @s.asset_dirs[:darkfish] = '.'

      @req.path = '/css/rdoc.css'

      @s.asset :darkfish, @req, @res

      assert_equal 'h1 { color: red }', @res.body
      assert_equal 'text/css',          @res.content_type
      assert_equal now.httpdate,        @res['last-modified']
    end
  end

  def test_do_GET
    touch_system_cache_path

    @req.path = '/ruby/Missing.html'

    @s.do_GET @req, @res

    assert_equal 404, @res.status
  end

  def test_do_GET_asset_darkfish
    temp_dir do
      FileUtils.mkdir 'css'
      FileUtils.touch 'css/rdoc.css'

      @s.asset_dirs[:darkfish] = '.'

      @req.path = '/css/rdoc.css'

      @s.do_GET @req, @res

      assert_equal 'text/css',          @res.content_type
    end
  end

  def test_do_GET_asset_json_index
    temp_dir do
      FileUtils.mkdir 'js'
      FileUtils.touch 'js/navigation.js'

      @s.asset_dirs[:json_index] = '.'

      @req.path = '/js/navigation.js'

      @s.do_GET @req, @res

      assert_equal 'application/javascript', @res.content_type
    end
  end

  def test_do_GET_error
    touch_system_cache_path

    def @req.path() raise 'no' end

    @s.do_GET @req, @res

    assert_equal 500, @res.status
  end

  def test_do_GET_mount_path
    @s = RDoc::Servlet.new @server, @stores, @cache, '/mount/path'

    temp_dir do
      FileUtils.mkdir 'css'
      FileUtils.touch 'css/rdoc.css'

      @s.asset_dirs[:darkfish] = '.'

      @req.path = '/mount/path/css/rdoc.css'.dup

      @s.do_GET @req, @res

      assert_equal 'text/css', @res.content_type
    end
  end

  def do_GET_not_found
    touch_system_cache_path

    @req.path = "/#{@spec.full_name}"

    @s.do_GET @req, @res

    assert_equal 404, @res.status
  end

  def test_do_GET_not_modified
    touch_system_cache_path
    @req.header['if-modified-since'] = [(Time.now + 10).httpdate]
    @req.path = '/ruby/Missing.html'

    assert_raise WEBrick::HTTPStatus::NotModified do
      @s.do_GET @req, @res
    end
  end

  def test_do_GET_root
    touch_system_cache_path

    @req.path = '/'

    @s.do_GET @req, @res

    assert_equal 'text/html',                                 @res.content_type
    assert_match %r%<title>Local RDoc Documentation</title>%, @res.body
  end

  def test_do_GET_root_search
    touch_system_cache_path

    @req.path = '/js/search_index.js'

    @s.do_GET @req, @res

    assert_equal 'application/javascript', @res.content_type, @res.body
  end

  def test_documentation_page_class
    store = RDoc::Store.new

    generator = @s.generator_for store

    file      = store.add_file 'file.rb'
    klass     = file.add_class RDoc::NormalClass, 'Klass'
                klass.add_class RDoc::NormalClass, 'Sub'

    @s.documentation_page store, generator, 'Klass::Sub.html', @req, @res

    assert_match %r%<title>class Klass::Sub - </title>%,            @res.body
    assert_match %r%<body id="top" role="document" class="class">%, @res.body
  end

  def test_documentation_page_not_found
    store = RDoc::Store.new

    generator = @s.generator_for store

    @req.path = '/ruby/Missing.html'

    @s.documentation_page store, generator, 'Missing.html', @req, @res

    assert_equal 404, @res.status
  end

  def test_documentation_page_page
    store = RDoc::Store.new

    generator = @s.generator_for store

    store.add_file 'README.rdoc', parser: RDoc::Parser::Simple

    @s.documentation_page store, generator, 'README_rdoc.html', @req, @res

    assert_match %r%<title>README - </title>%, @res.body
    assert_match %r%<body [^>]+ class="file">%,      @res.body
  end

  def test_documentation_page_page_with_nesting
    store = RDoc::Store.new

    generator = @s.generator_for store

    store.add_file 'nesting/README.rdoc', parser: RDoc::Parser::Simple

    @s.documentation_page store, generator, 'nesting/README_rdoc.html', @req, @res

    assert_equal 200, @res.status
  end

  def test_documentation_source
    store, path = @s.documentation_source '/ruby/Object.html'

    assert_equal @system_dir, store.path

    assert_equal 'Object.html', path
  end

  def test_documentation_source_cached
    cached_store = RDoc::Store.new

    @stores['ruby'] = cached_store

    store, path = @s.documentation_source '/ruby/Object.html'

    assert_same cached_store, store

    assert_equal 'Object.html', path
  end

  def test_error
    e = RuntimeError.new 'foo'
    e.set_backtrace caller

    @s.error e, @req, @res

    assert_equal 'text/html',      @res.content_type
    assert_equal 500,              @res.status
    assert_match %r%<title>Error%, @res.body
  end

  def test_generator_for
    store = RDoc::Store.new
    store.main  = 'MAIN_PAGE.rdoc'
    store.title = 'Title'

    generator = @s.generator_for store

    refute generator.file_output

    assert_equal '..', generator.asset_rel_path

    assert_equal 'MAIN_PAGE.rdoc', @s.options.main_page
    assert_equal 'Title',          @s.options.title

    assert_kind_of RDoc::RDoc, store.rdoc
    assert_same generator, store.rdoc.generator
  end

  def test_if_modified_since
    omit 'File.utime on directory not supported' if Gem.win_platform?

    temp_dir do
      now = Time.now
      File.utime now, now, '.'

      @s.if_modified_since @req, @res, '.'

      assert_equal now.to_i, Time.parse(@res['last-modified']).to_i
    end
  end

  def test_if_modified_since_not_modified
    omit 'File.utime on directory not supported' if Gem.win_platform?

    temp_dir do
      now = Time.now
      File.utime now, now, '.'

      @req.header['if-modified-since'] = [(now + 10).httpdate]

      assert_raise WEBrick::HTTPStatus::NotModified do
        @s.if_modified_since @req, @res, '.'
      end

      assert_equal now.to_i, Time.parse(@res['last-modified']).to_i
    end
  end

  def test_installed_docs
    touch_system_cache_path
    touch_extra_cache_path

    expected = [
      ['My Extra Documentation', 'extra-1/', true, :extra,
        @extra_dirs[0]],
      ['Extra Documentation', 'extra-2/', false, :extra,
        @extra_dirs[1]],
      ['Ruby Documentation', 'ruby/', true,  :system,
        @system_dir],
      ['Site Documentation', 'site/', false, :site,
        File.join(@base, 'site')],
      ['Home Documentation', 'home/', false, :home,
        RDoc::RI::Paths::HOMEDIR],
      ['spec-1.0', 'spec-1.0/',       false, :gem,
        File.join(@spec.doc_dir, 'ri')],
    ]

    assert_equal expected, @s.installed_docs
  end

  def test_not_found
    generator = @s.generator_for RDoc::Store.new

    @req.path = '/ruby/Missing.html'

    @s.not_found generator, @req, @res

    assert_equal 404,                                @res.status
    assert_match %r%<title>Not Found</title>%,       @res.body
    assert_match %r%<kbd>/ruby/Missing\.html</kbd>%, @res.body
  end

  def test_not_found_message
    generator = @s.generator_for RDoc::Store.new

    @req.path = '/ruby/Missing.html'

    @s.not_found generator, @req, @res, 'woo, this is a message'

    assert_equal 404,                          @res.status
    assert_match %r%<title>Not Found</title>%, @res.body
    assert_match %r%woo, this is a message%,   @res.body
  end

  def test_ri_paths
    paths = @s.ri_paths

    expected = [
      [@extra_dirs[0],                 :extra],
      [@extra_dirs[1],                 :extra],
      [@system_dir,                    :system],
      [File.join(@base, 'site'),       :site],
      [RDoc::RI::Paths::HOMEDIR,       :home],
      [File.join(@spec.doc_dir, 'ri'), :gem],
    ]

    assert_equal expected, paths.to_a
  end

  def test_root
    @s.root @req, @res

    assert_equal 'text/html',                                 @res.content_type
    assert_match %r%<title>Local RDoc Documentation</title>%, @res.body
  end

  def test_root_search
    touch_system_cache_path
    touch_extra_cache_path

    @s.root_search @req, @res

    assert_equal 'application/javascript', @res.content_type

    @res.body =~ /\{.*\}/

    index = JSON.parse $&

    expected = {
      'index' => {
        'searchIndex' => %w[
          My\ Extra\ Documentation
          Ruby\ Documentation
        ],
        'longSearchIndex' => %w[
          My\ Extra\ Documentation
          Ruby\ Documentation
        ],
        'info' => [
          ['My Extra Documentation', '', @extra_dirs[0], '',
            'My Extra Documentation'],
          ['Ruby Documentation', '', 'ruby', '',
            'Documentation for the Ruby standard library'],
        ],
      }
    }

    assert_equal expected, index
  end

  def test_show_documentation_index
    touch_system_cache_path

    @req.path = '/ruby'

    @s.show_documentation @req, @res

    assert_equal 'text/html',                               @res.content_type
    assert_match %r%<title>Standard Library Documentation%, @res.body
  end

  def test_show_documentation_table_of_contents
    touch_system_cache_path

    @req.path = '/ruby/table_of_contents.html'

    @s.show_documentation @req, @res

    assert_equal 'text/html',         @res.content_type
    assert_match %r%<title>Table of Contents - Standard Library Documentation%,
                 @res.body
  end

  def test_show_documentation_page
    touch_system_cache_path

    @req.path = '/ruby/Missing.html'

    @s.show_documentation @req, @res

    assert_equal 404, @res.status
  end

  def test_show_documentation_search_index
    touch_system_cache_path

    @req.path = '/ruby/js/search_index.js'

    @s.show_documentation @req, @res

    assert_equal 'application/javascript', @res.content_type
    assert_match %r%\Avar search_data =%,  @res.body
  end

  def test_store_for_gem
    ri_dir = File.join @gem_doc_dir, 'spec-1.0', 'ri'
    FileUtils.mkdir_p ri_dir
    FileUtils.touch File.join ri_dir, 'cache.ri'

    store = @s.store_for 'spec-1.0'

    assert_equal File.join(@gem_doc_dir, 'spec-1.0', 'ri'), store.path
    assert_equal :gem, store.type
  end

  def test_store_for_home
    store = @s.store_for 'home'

    assert_equal @home_dir, store.path
    assert_equal :home, store.type
  end

  def test_store_for_missing_documentation
    FileUtils.mkdir_p(File.join @gem_doc_dir, 'spec-1.0', 'ri')

    e = assert_raise WEBrick::HTTPStatus::NotFound do
      @s.store_for 'spec-1.0'
    end

    assert_equal 'Could not find documentation for "spec-1.0". Please run `gem rdoc --ri gem_name`',
                 e.message
  end

  def test_store_for_missing_gem
    e = assert_raise WEBrick::HTTPStatus::NotFound do
      @s.store_for 'missing'
    end

    assert_equal 'Could not find gem "missing". Are you sure you installed it?',
                 e.message
  end

  def test_store_for_ruby
    store = @s.store_for 'ruby'

    assert_equal @system_dir, store.path
    assert_equal :system, store.type
  end

  def test_store_for_site
    store = @s.store_for 'site'

    assert_equal File.join(@base, 'site'), store.path
    assert_equal :site, store.type
  end

  def test_store_for_extra
    store = @s.store_for 'extra-1'

    assert_equal @extra_dirs.first, store.path
    assert_equal :extra, store.type
  end

  def touch_system_cache_path
    store = RDoc::Store.new @system_dir
    store.title = 'Standard Library Documentation'

    FileUtils.mkdir_p File.dirname store.cache_path

    store.save
  end

  def touch_extra_cache_path
    store = RDoc::Store.new @extra_dirs.first
    store.title = 'My Extra Documentation'

    FileUtils.mkdir_p File.dirname store.cache_path

    store.save
  end

end
