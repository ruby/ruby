# frozen_string_literal: true

require_relative "../command"
require_relative "../local_remote_options"
require_relative "../version_option"
require_relative "../gemcutter_utilities"
require_relative "../package"

class Gem::Commands::PushCommand < Gem::Command
  include Gem::LocalRemoteOptions
  include Gem::VersionOption
  include Gem::GemcutterUtilities

  def description # :nodoc:
    <<-EOF
The push command uploads a gem to the push server (the default is
https://rubygems.org) and adds it to the index.

The gem can be removed from the index and deleted from the server using the yank
command.  For further discussion see the help for the yank command.

The push command will use ~/.gem/credentials to authenticate to a server, but you can use the RubyGems environment variable GEM_HOST_API_KEY to set the api key to authenticate. If the :credential_store: gemrc option (or RUBYGEMS_CREDENTIAL_STORE environment variable) is set, the API key is stored in and read from the credential store it selects instead of ~/.gem/credentials.

The API key to send is resolved in this order: the GEM_HOST_API_KEY environment variable, the --key option, the host's own key in the credential store (when :credential_store: is set), the host's own key in ~/.gem/credentials, then the default RubyGems.org key from either place. The first one found is used.
    EOF
  end

  def arguments # :nodoc:
    "GEM       built gem to push up"
  end

  def usage # :nodoc:
    "#{program_name} GEM"
  end

  def initialize
    super "push", "Push a gem up to the gem server", host: host, attestations: []

    @user_defined_host = false

    add_proxy_option
    add_key_option
    add_otp_option

    add_option("--host HOST",
               "Push to another gemcutter-compatible host",
               "  (e.g. https://rubygems.org)") do |value, options|
      options[:host] = value
      @user_defined_host = true
    end

    add_option("--platform PLATFORM",
               "Push a gem for a specific platform",
               "  (e.g. x86_64-darwin-20)") do |value, options|
      options[:platform] = value
    end

    add_ruby_abi_option("push", "  (e.g. 3.4)")

    add_option("--attestation FILE",
                "Push with sigstore attestations",
                "  (FILE must be a JSON sigstore bundle)") do |value, options|
      options[:attestations] << value
    end

    @host = nil
  end

  def execute
    gem_name = if options[:platform] || options[:ruby_abi]
      resolve_gem_name(get_all_gem_names)
    else
      get_one_gem_name
    end

    default_gem_server, push_host = get_hosts_for(gem_name)

    @host = if @user_defined_host
      options[:host]
    elsif default_gem_server
      default_gem_server
    elsif push_host
      push_host
    else
      options[:host]
    end

    sign_in @host, scope: get_push_scope

    send_gem(gem_name)
  end

  def send_gem(name)
    args = [:post, "api/v1/gems"]

    _, push_host = get_hosts_for(name)

    @host ||= push_host

    # Always include @host, even if it's nil
    args += [@host, push_host]

    say "Pushing gem to #{@host || Gem.host}..."

    response = send_push_request(name, args)

    with_response response
  end

  private

  def resolve_gem_name(names)
    platform = options[:platform] && Gem::Platform.new(options[:platform])
    ruby_abi = options[:ruby_abi]

    candidates = names.filter_map do |name|
      [name, Gem::Package.new(name).spec]
    rescue Gem::Package::FormatError => e
      alert_warning "Skipping #{name}: #{e.message}"
      nil
    end

    matches = candidates.select do |_, spec|
      (!platform || spec.platform == platform) &&
        (!ruby_abi || (Gem::ContentAddress.eligible?(spec) && spec.ruby_abi == ruby_abi))
    end

    raise Gem::CommandLineError, "No gem matched #{gem_name_selector_description}" if matches.empty?
    raise Gem::CommandLineError, multiple_matches_message(matches) if matches.length > 1

    matches.first.first
  end

  def gem_name_selector_description
    selectors = []
    selectors << "platform #{options[:platform]}" if options[:platform]
    selectors << "Ruby ABI #{options[:ruby_abi]}" if options[:ruby_abi]
    selectors.join(" and ")
  end

  def multiple_matches_message(matches)
    message = "Multiple gems matched #{gem_name_selector_description}: #{matches.map(&:first).join(", ")}"

    if options[:platform] && !options[:ruby_abi]
      ruby_abis = matches.filter_map {|_, spec| spec.ruby_abi }.uniq.sort
      message += "\nSpecify --ruby-abi with one of: #{ruby_abis.join(", ")}" unless ruby_abis.empty?
      message += "\nTo push a gem without a Ruby ABI, pass the exact filename." if matches.any? {|_, spec| spec.ruby_abi.nil? }
    elsif options[:ruby_abi] && !options[:platform]
      platforms = matches.map {|_, spec| spec.platform.to_s }.uniq.sort
      message += "\nSpecify --platform with one of: #{platforms.join(", ")}" unless platforms.empty?
    end

    message
  end

  def send_push_request(name, args)
    # Always honor explicit --attestation option
    # Auto-attestation is only supported on rubygems.org with GitHub Actions (not JRuby)
    if options[:attestations].any? || (RUBY_ENGINE != "jruby" && attestation_supported_host? && ENV["GITHUB_ACTIONS"] == "true")
      send_push_request_with_attestation(name, args)
    else
      send_push_request_without_attestation(name, args)
    end
  end

  def send_push_request_without_attestation(name, args)
    scope = get_push_scope
    rubygems_api_request(*args, scope: scope) do |request|
      body = Gem.read_binary name
      request.body = body
      request.add_field "Content-Type",   "application/octet-stream"
      request.add_field "Content-Length", request.body.size
      request.add_field "Authorization", api_key
    end
  end

  def send_push_request_with_attestation(name, args)
    attestations = if options[:attestations].any?
      options[:attestations].map do |attestation|
        load_attestation(attestation)
      end
    else
      # Only the opportunistic signing step falls back. The request below stays
      # outside this rescue because once the server may have seen the attested
      # push, a network error must not trigger an unattested retry.
      begin
        [attest!(name)]
      rescue StandardError => e
        message = "Failed to create an attestation, pushing without one.\n"
        message += if Gem.configuration.really_verbose
          e.full_message
        else
          e.message
        end
        alert_warning message
        return send_push_request_without_attestation(name, args)
      end
    end
    bundles = "[" + attestations.join(",") + "]"

    rubygems_api_request(*args, scope: get_push_scope) do |request|
      request.set_form([
        ["gem", Gem.read_binary(name), { filename: name, content_type: "application/octet-stream" }],
        ["attestations", bundles, { content_type: "application/json" }],
      ], "multipart/form-data")
      request.add_field "Authorization", api_key
    end
  end

  def load_attestation(file)
    data = begin
      Gem.read_binary(file)
    rescue SystemCallError, IOError, ArgumentError => e
      raise Gem::Exception, "Failed to read attestation #{file}: #{e.message}"
    end
    validate_attestation_json(data, file)
  end

  def validate_attestation_json(data, source)
    require "json"

    parsed = begin
      JSON.parse(data)
    rescue JSON::ParserError => e
      raise Gem::Exception, "Attestation #{source} is not valid JSON: #{e.message}"
    end
    raise Gem::Exception, "Attestation #{source} is not a JSON object" unless parsed.is_a?(Hash)
    data
  end

  def attest!(name)
    require "open3"
    require "shellwords"
    require "tempfile"

    env = defined?(Bundler.unbundled_env) ? Bundler.unbundled_env : ENV.to_h

    Tempfile.create([File.basename(name, ".*"), ".sigstore.json"]) do |tempfile|
      tempfile.close
      bundle = tempfile.path

      # Gem.ruby is quoted if it contains whitespace, so split it into argv
      # elements to keep the quotes out of the spawned command.
      out, st = Open3.capture2e(
        env,
        *Shellwords.split(Gem.ruby), "-S", "gem", "exec", "--conservative",
        "sigstore-cli", "sign", name, "--bundle", bundle,
        unsetenv_others: true
      )
      raise Gem::Exception, "Failed to sign gem:\n\n#{out}" unless st.success?

      validate_attestation_json(Gem.read_binary(bundle), "generated by sigstore-cli")
    end
  end

  def get_hosts_for(name)
    gem_metadata = Gem::Package.new(name).spec.metadata

    [
      gem_metadata["default_gem_server"],
      gem_metadata["allowed_push_host"],
    ]
  end

  def get_push_scope
    :push_rubygem
  end

  def attestation_supported_host?
    host = (@host || Gem.host).to_s.chomp("/")
    host == Gem::DEFAULT_HOST
  end
end
