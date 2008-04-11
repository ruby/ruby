require 'webrick'
require 'yaml'
require 'zlib'
require 'erb'

require 'rubygems'

##
# Gem::Server and allows users to serve gems for consumption by
# `gem --remote-install`.
#
# gem_server starts an HTTP server on the given port and serves the folowing:
# * "/" - Browsing of gem spec files for installed gems
# * "/Marshal" - Full SourceIndex dump of metadata for installed gems
# * "/yaml" - YAML dump of metadata for installed gems - deprecated
# * "/gems" - Direct access to download the installable gems
#
# == Usage
#
#   gem server [-p portnum] [-d gem_path]
#
# port_num:: The TCP port the HTTP server will bind to
# gem_path::
#   Root gem directory containing both "cache" and "specifications"
#   subdirectories.
class Gem::Server

  include Gem::UserInteraction

  DOC_TEMPLATE = <<-'WEBPAGE'
  <?xml version="1.0" encoding="iso-8859-1"?>
  <!DOCTYPE html
       PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
       "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">

  <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
  <head>
    <title>RubyGems Documentation Index</title>
    <meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1" />
    <link rel="stylesheet" href="gem-server-rdoc-style.css" type="text/css" media="screen" />
  </head>
  <body>
    <div id="fileHeader">
      <h1>RubyGems Documentation Index</h1>
    </div>
    <!-- banner header -->

  <div id="bodyContent">
    <div id="contextContent">
      <div id="description">
        <h1>Summary</h1>
  <p>There are <%=values["gem_count"]%> gems installed:</p>
  <p>
  <%= values["specs"].map { |v| "<a href=\"##{v["name"]}\">#{v["name"]}</a>" }.join ', ' %>.
  <h1>Gems</h1>

  <dl>
  <% values["specs"].each do |spec| %>
  	<dt>
  	<% if spec["first_name_entry"] then %>
  	  <a name="<%=spec["name"]%>"></a>
  	<% end %>

  	<b><%=spec["name"]%> <%=spec["version"]%></b>

  	<% if spec["rdoc_installed"] then %>
  	  <a href="<%=spec["doc_path"]%>">[rdoc]</a>
  	<% else %>
  	  <span title="rdoc not installed">[rdoc]</span>
  	<% end %>

  	<% if spec["homepage"] then %>
  		<a href="<%=spec["homepage"]%>" title="<%=spec["homepage"]%>">[www]</a>
  	<% else %>
  		<span title="no homepage available">[www]</span>
  	<% end %>

  	<% if spec["has_deps"] then %>
  	 - depends on
  		<%= spec["dependencies"].map { |v| "<a href=\"##{v["name"]}\">#{v["name"]}</a>" }.join ', ' %>.
  	<% end %>
  	</dt>
  	<dd>
  	<%=spec["summary"]%>
  	<% if spec["executables"] then %>
  	  <br/>

  		<% if spec["only_one_executable"] then %>
  		    Executable is
  		<% else %>
  		    Executables are
  		<%end%>

  		<%= spec["executables"].map { |v| "<span class=\"context-item-name\">#{v["executable"]}</span>"}.join ', ' %>.

  	<%end%>
  	<br/>
  	<br/>
  	</dd>
  <% end %>
  </dl>

      </div>
     </div>
    </div>
  <div id="validator-badges">
    <p><small><a href="http://validator.w3.org/check/referer">[Validate]</a></small></p>
  </div>
  </body>
  </html>
  WEBPAGE

  # CSS is copy & paste from rdoc-style.css, RDoc V1.0.1 - 20041108
  RDOC_CSS = <<-RDOCCSS
body {
    font-family: Verdana,Arial,Helvetica,sans-serif;
    font-size:   90%;
    margin: 0;
    margin-left: 40px;
    padding: 0;
    background: white;
}

h1,h2,h3,h4 { margin: 0; color: #efefef; background: transparent; }
h1 { font-size: 150%; }
h2,h3,h4 { margin-top: 1em; }

a { background: #eef; color: #039; text-decoration: none; }
a:hover { background: #039; color: #eef; }

/* Override the base stylesheets Anchor inside a table cell */
td > a {
  background: transparent;
  color: #039;
  text-decoration: none;
}

/* and inside a section title */
.section-title > a {
  background: transparent;
  color: #eee;
  text-decoration: none;
}

/* === Structural elements =================================== */

div#index {
    margin: 0;
    margin-left: -40px;
    padding: 0;
    font-size: 90%;
}


div#index a {
    margin-left: 0.7em;
}

div#index .section-bar {
   margin-left: 0px;
   padding-left: 0.7em;
   background: #ccc;
   font-size: small;
}


div#classHeader, div#fileHeader {
    width: auto;
    color: white;
    padding: 0.5em 1.5em 0.5em 1.5em;
    margin: 0;
    margin-left: -40px;
    border-bottom: 3px solid #006;
}

div#classHeader a, div#fileHeader a {
    background: inherit;
    color: white;
}

div#classHeader td, div#fileHeader td {
    background: inherit;
    color: white;
}


div#fileHeader {
    background: #057;
}

div#classHeader {
    background: #048;
}


.class-name-in-header {
  font-size:  180%;
  font-weight: bold;
}


div#bodyContent {
    padding: 0 1.5em 0 1.5em;
}

div#description {
    padding: 0.5em 1.5em;
    background: #efefef;
    border: 1px dotted #999;
}

div#description h1,h2,h3,h4,h5,h6 {
    color: #125;;
    background: transparent;
}

div#validator-badges {
    text-align: center;
}
div#validator-badges img { border: 0; }

div#copyright {
    color: #333;
    background: #efefef;
    font: 0.75em sans-serif;
    margin-top: 5em;
    margin-bottom: 0;
    padding: 0.5em 2em;
}


/* === Classes =================================== */

table.header-table {
    color: white;
    font-size: small;
}

.type-note {
    font-size: small;
    color: #DEDEDE;
}

.xxsection-bar {
    background: #eee;
    color: #333;
    padding: 3px;
}

.section-bar {
   color: #333;
   border-bottom: 1px solid #999;
    margin-left: -20px;
}


.section-title {
    background: #79a;
    color: #eee;
    padding: 3px;
    margin-top: 2em;
    margin-left: -30px;
    border: 1px solid #999;
}

.top-aligned-row {  vertical-align: top }
.bottom-aligned-row { vertical-align: bottom }

/* --- Context section classes ----------------------- */

.context-row { }
.context-item-name { font-family: monospace; font-weight: bold; color: black; }
.context-item-value { font-size: small; color: #448; }
.context-item-desc { color: #333; padding-left: 2em; }

/* --- Method classes -------------------------- */
.method-detail {
    background: #efefef;
    padding: 0;
    margin-top: 0.5em;
    margin-bottom: 1em;
    border: 1px dotted #ccc;
}
.method-heading {
  color: black;
  background: #ccc;
  border-bottom: 1px solid #666;
  padding: 0.2em 0.5em 0 0.5em;
}
.method-signature { color: black; background: inherit; }
.method-name { font-weight: bold; }
.method-args { font-style: italic; }
.method-description { padding: 0 0.5em 0 0.5em; }

/* --- Source code sections -------------------- */

a.source-toggle { font-size: 90%; }
div.method-source-code {
    background: #262626;
    color: #ffdead;
    margin: 1em;
    padding: 0.5em;
    border: 1px dashed #999;
    overflow: hidden;
}

div.method-source-code pre { color: #ffdead; overflow: hidden; }

/* --- Ruby keyword styles --------------------- */

.standalone-code { background: #221111; color: #ffdead; overflow: hidden; }

.ruby-constant  { color: #7fffd4; background: transparent; }
.ruby-keyword { color: #00ffff; background: transparent; }
.ruby-ivar    { color: #eedd82; background: transparent; }
.ruby-operator  { color: #00ffee; background: transparent; }
.ruby-identifier { color: #ffdead; background: transparent; }
.ruby-node    { color: #ffa07a; background: transparent; }
.ruby-comment { color: #b22222; font-weight: bold; background: transparent; }
.ruby-regexp  { color: #ffa07a; background: transparent; }
.ruby-value   { color: #7fffd4; background: transparent; }
  RDOCCSS

  def self.run(options)
    new(options[:gemdir], options[:port], options[:daemon]).run
  end

  def initialize(gemdir, port, daemon)
    Socket.do_not_reverse_lookup = true

    @gemdir = gemdir
    @port = port
    @daemon = daemon
    logger = WEBrick::Log.new nil, WEBrick::BasicLog::FATAL
    @server = WEBrick::HTTPServer.new :DoNotListen => true, :Logger => logger

    @spec_dir = File.join @gemdir, "specifications"
    @source_index = Gem::SourceIndex.from_gems_in @spec_dir
  end

  def quick(req, res)
    res['content-type'] = 'text/plain'
    res['date'] = File.stat(@spec_dir).mtime

    case req.request_uri.request_uri
    when '/quick/index' then
      res.body << @source_index.map { |name,_| name }.join("\n")
    when '/quick/index.rz' then
      index = @source_index.map { |name,_| name }.join("\n")
      res.body << Zlib::Deflate.deflate(index)
    when %r|^/quick/(Marshal.#{Regexp.escape Gem.marshal_version}/)?(.*?)-([0-9.]+)(-.*?)?\.gemspec\.rz$| then
      dep = Gem::Dependency.new $2, $3
      specs = @source_index.search dep

      selector = [$2, $3, $4].map { |s| s.inspect }.join ' '

      platform = if $4 then
                   Gem::Platform.new $4.sub(/^-/, '')
                 else
                   Gem::Platform::RUBY
                 end

      specs = specs.select { |s| s.platform == platform }

      if specs.empty? then
        res.status = 404
        res.body = "No gems found matching #{selector}"
      elsif specs.length > 1 then
        res.status = 500
        res.body = "Multiple gems found matching #{selector}"
      elsif $1 then # marshal quickindex instead of YAML
        res.body << Zlib::Deflate.deflate(Marshal.dump(specs.first))
      else # deprecated YAML format
        res.body << Zlib::Deflate.deflate(specs.first.to_yaml)
      end
    else
      res.status = 404
      res.body = "#{req.request_uri} not found"
    end
  end

  def run
    @server.listen nil, @port

    say "Starting gem server on http://localhost:#{@port}/"

    WEBrick::Daemon.start if @daemon

    @server.mount_proc("/yaml") do |req, res|
      res['content-type'] = 'text/plain'
      res['date'] = File.stat(@spec_dir).mtime
      if req.request_method == 'HEAD' then
        res['content-length'] = @source_index.to_yaml.length
      else
        res.body << @source_index.to_yaml
      end
    end

    @server.mount_proc("/Marshal") do |req, res|
      res['content-type'] = 'text/plain'
      res['date'] = File.stat(@spec_dir).mtime
      if req.request_method == 'HEAD' then
        res['content-length'] = Marshal.dump(@source_index).length
      else
        res.body << Marshal.dump(@source_index)
      end
    end

    @server.mount_proc("/quick/", &method(:quick))

    @server.mount_proc("/gem-server-rdoc-style.css") do |req, res|
      res['content-type'] = 'text/css'
      res['date'] = File.stat(@spec_dir).mtime
      res.body << RDOC_CSS
    end

    @server.mount_proc("/") do |req, res|
      specs = []
      total_file_count = 0

      @source_index.each do |path, spec|
        total_file_count += spec.files.size
        deps = spec.dependencies.collect { |dep|
          { "name"    => dep.name, 
            "version" => dep.version_requirements.to_s, }
        }
        deps = deps.sort_by { |dep| [dep["name"].downcase, dep["version"]] }
        deps.last["is_last"] = true unless deps.empty?

        # executables
        executables = spec.executables.sort.collect { |exec| {"executable" => exec} }
        executables = nil if executables.empty?
        executables.last["is_last"] = true if executables

        specs << {
          "authors"        => spec.authors.sort.join(", "),
          "date"           => spec.date.to_s,
          "dependencies"   => deps,
          "doc_path"       => ('/doc_root/' + spec.full_name + '/rdoc/index.html'),
          "executables"    => executables,
          "only_one_executable" => (executables && executables.size==1),
          "full_name"      => spec.full_name,
          "has_deps"       => !deps.empty?,
          "homepage"       => spec.homepage,
          "name"           => spec.name,
          "rdoc_installed" => Gem::DocManager.new(spec).rdoc_installed?,
          "summary"        => spec.summary,
          "version"        => spec.version.to_s,
        }
      end

      specs << {
        "authors" => "Chad Fowler, Rich Kilmer, Jim Weirich, Eric Hodel and others",
        "dependencies" => [],
        "doc_path" => "/doc_root/rubygems-#{Gem::RubyGemsVersion}/rdoc/index.html",
        "executables" => [{"executable" => 'gem', "is_last" => true}],
        "only_one_executable" => true,
        "full_name" => "rubygems-#{Gem::RubyGemsVersion}",
        "has_deps" => false,
        "homepage" => "http://rubygems.org/",
        "name" => 'rubygems',
        "rdoc_installed" => true,
        "summary" => "RubyGems itself",
        "version" => Gem::RubyGemsVersion,
      }

      specs = specs.sort_by { |spec| [spec["name"].downcase, spec["version"]] }
      specs.last["is_last"] = true

      # tag all specs with first_name_entry 
      last_spec = nil
      specs.each do |spec|
        is_first = last_spec.nil? || (last_spec["name"].downcase != spec["name"].downcase)
        spec["first_name_entry"] = is_first
        last_spec = spec
      end

      # create page from template
      template = ERB.new(DOC_TEMPLATE)
      res['content-type'] = 'text/html'
      values = { "gem_count" => specs.size.to_s, "specs" => specs,
                             "total_file_count" => total_file_count.to_s }
      result = template.result binding
      res.body = result
    end

    paths = { "/gems" => "/cache/", "/doc_root" => "/doc/" }
    paths.each do |mount_point, mount_dir|
      @server.mount(mount_point, WEBrick::HTTPServlet::FileHandler,
              File.join(@gemdir, mount_dir), true)
    end

    trap("INT") { @server.shutdown; exit! }
    trap("TERM") { @server.shutdown; exit! }

    @server.start
  end

end

