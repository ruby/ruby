require 'rubygems/command'
require 'rubygems/server'

class Gem::Commands::ServerCommand < Gem::Command

  def initialize
    super 'server', 'Documentation and gem repository HTTP server',
          :port => 8808, :gemdir => Gem.dir, :daemon => false

    add_option '-p', '--port=PORT', Integer,
               'port to listen on' do |port, options|
      options[:port] = port
    end

    add_option '-d', '--dir=GEMDIR',
               'directory from which to serve gems' do |gemdir, options|
      options[:gemdir] = File.expand_path gemdir
    end

    add_option '--[no-]daemon', 'run as a daemon' do |daemon, options|
      options[:daemon] = daemon
    end
  end

  def defaults_str # :nodoc:
    "--port 8808 --dir #{Gem.dir} --no-daemon"
  end

  def description # :nodoc:
    <<-EOF
The server command starts up a web server that hosts the RDoc for your
installed gems and can operate as a server for installation of gems on other
machines.

The cache files for installed gems must exist to use the server as a source
for gem installation.

To install gems from a running server, use `gem install GEMNAME --source
http://gem_server_host:8808`
    EOF
  end

  def execute
    Gem::Server.run options
  end

end

