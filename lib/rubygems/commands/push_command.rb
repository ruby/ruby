require 'rubygems/command'
require 'rubygems/local_remote_options'
require 'rubygems/gemcutter_utilities'
require 'rubygems/package'

class Gem::Commands::PushCommand < Gem::Command
  include Gem::LocalRemoteOptions
  include Gem::GemcutterUtilities

  def description # :nodoc:
    'Push a gem up to RubyGems.org'
  end

  def arguments # :nodoc:
    "GEM       built gem to push up"
  end

  def usage # :nodoc:
    "#{program_name} GEM"
  end

  def initialize
    super 'push', description
    add_proxy_option
    add_key_option

    add_option(
      '--host HOST',
      'Push to another gemcutter-compatible host'
    ) do |value, options|
      options[:host] = value
    end
  end

  def execute
    sign_in
    send_gem get_one_gem_name
  end

  def send_gem name
    args = [:post, "api/v1/gems"]

    latest_rubygems_version = Gem.latest_rubygems_version

    if latest_rubygems_version < Gem.rubygems_version and
         Gem.rubygems_version.prerelease? and
         Gem::Version.new('2.0.0.preview3') != Gem.rubygems_version then
      alert_error <<-ERROR
You are using a beta release of RubyGems (#{Gem::VERSION}) which is not
allowed to push gems.  Please downgrade or upgrade to a release version.

The latest released RubyGems version is #{latest_rubygems_version}
      ERROR
      terminate_interaction 1
    end

    host = options[:host]
    unless host
      if gem_data = Gem::Package.new(name) then
        host = gem_data.spec.metadata['default_gem_server']
      end
    end

    args << host if host

    say "Pushing gem to #{host || Gem.host}..."

    response = rubygems_api_request(*args) do |request|
      request.body = Gem.read_binary name
      request.add_field "Content-Length", request.body.size
      request.add_field "Content-Type",   "application/octet-stream"
      request.add_field "Authorization",  api_key
    end

    with_response response
  end

end

