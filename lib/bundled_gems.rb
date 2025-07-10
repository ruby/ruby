# -*- frozen-string-literal: true -*-

module Gem::BUNDLED_GEMS # :nodoc:
  SINCE = {
    "racc" => "3.3.0",
    "abbrev" => "3.4.0",
    "base64" => "3.4.0",
    "bigdecimal" => "3.4.0",
    "csv" => "3.4.0",
    "drb" => "3.4.0",
    "getoptlong" => "3.4.0",
    "mutex_m" => "3.4.0",
    "nkf" => "3.4.0",
    "observer" => "3.4.0",
    "resolv-replace" => "3.4.0",
    "rinda" => "3.4.0",
    "syslog" => "3.4.0",
    "ostruct" => "3.5.0",
    "pstore" => "3.5.0",
    "rdoc" => "3.5.0",
    "win32ole" => "3.5.0",
    "fiddle" => "3.5.0",
    "logger" => "3.5.0",
    "benchmark" => "3.5.0",
    "irb" => "3.5.0",
    "reline" => "3.5.0",
    # "readline" => "3.5.0", # This is wrapper for reline. We don't warn for this.
    "tsort" => "3.6.0",
  }.freeze

  EXACT = {
    "kconv" => "nkf",
  }.freeze

  WARNED = {}                   # unfrozen

  conf = ::RbConfig::CONFIG
  LIBDIR = (conf["rubylibdir"] + "/").freeze
  ARCHDIR = (conf["rubyarchdir"] + "/").freeze
  dlext = [conf["DLEXT"], "so"].uniq
  DLEXT = /\.#{Regexp.union(dlext)}\z/
  LIBEXT = /\.#{Regexp.union("rb", *dlext)}\z/

  def self.replace_require(specs)
    return if [::Kernel.singleton_class, ::Kernel].any? {|klass| klass.respond_to?(:no_warning_require) }

    spec_names = specs.to_a.each_with_object({}) {|spec, h| h[spec.name] = true }

    [::Kernel.singleton_class, ::Kernel].each do |kernel_class|
      kernel_class.send(:alias_method, :no_warning_require, :require)
      kernel_class.send(:define_method, :require) do |name|
        if message = ::Gem::BUNDLED_GEMS.warning?(name, specs: spec_names)
          Kernel.warn message, uplevel: ::Gem::BUNDLED_GEMS.uplevel
        end
        kernel_class.send(:no_warning_require, name)
      end
      if kernel_class == ::Kernel
        kernel_class.send(:private, :require)
      else
        kernel_class.send(:public, :require)
      end
    end
  end

  def self.uplevel
    frame_count = 0
    require_labels = ["replace_require", "require"]
    uplevel = 0
    require_found = false
    Thread.each_caller_location do |cl|
      frame_count += 1

      if require_found
        unless require_labels.include?(cl.base_label)
          return uplevel
        end
      else
        if require_labels.include?(cl.base_label)
          require_found = true
        end
      end
      uplevel += 1
      # Don't show script name when bundle exec and call ruby script directly.
      if cl.path.end_with?("bundle")
        return
      end
    end
    require_found ? 1 : (frame_count - 1).nonzero?
  end

  def self.warning?(name, specs: nil)
    # name can be a feature name or a file path with String or Pathname
    feature = File.path(name).sub(LIBEXT, "")

    # The actual checks needed to properly identify the gem being required
    # are costly (see [Bug #20641]), so we first do a much cheaper check
    # to exclude the vast majority of candidates.
    subfeature = if feature.include?("/")
      # bootsnap expands `require "csv"` to `require "#{LIBDIR}/csv.rb"`,
      # and `require "syslog"` to `require "#{ARCHDIR}/syslog.so"`.
      feature.delete_prefix!(ARCHDIR)
      feature.delete_prefix!(LIBDIR)
      # 1. A segment for the EXACT mapping and SINCE check
      # 2. A segment for the SINCE check for dashed names
      # 3. A segment to check if there's a subfeature
      segments = feature.split("/", 3)
      name = segments.shift
      name = EXACT[name] || name
      if !SINCE[name]
        name = "#{name}-#{segments.shift}"
        return unless SINCE[name]
      end
      segments.any?
    else
      name = EXACT[feature] || feature
      return unless SINCE[name]
      false
    end

    return if specs.include?(name)

    return if WARNED[name]
    WARNED[name] = true

    level = RUBY_VERSION < SINCE[name] ? :warning : :error

    if subfeature
      "#{feature} is found in #{name}, which"
    else
      "#{feature} #{level == :warning ? "was loaded" : "used to be loaded"} from the standard library, but"
    end + build_message(name, level)
  end

  def self.build_message(name, level)
    msg = if level == :warning
      " will no longer be part of the default gems starting from Ruby #{SINCE[name]}"
    else
      " is not part of the default gems since Ruby #{SINCE[name]}."
    end

    if defined?(Bundler)
      motivation = level == :warning ? "silence this warning" : "fix this error"
      msg += "\nYou can add #{name} to your Gemfile or gemspec to #{motivation}."

      # We detect the gem name from caller_locations. First we walk until we find `require`
      # then take the first frame that's not from `require`.
      #
      # Additionally, we need to skip Bootsnap and Zeitwerk if present, these
      # gems decorate Kernel#require, so they are not really the ones issuing
      # the require call users should be warned about. Those are upwards.
      frames_to_skip = 3
      location = nil
      require_found = false
      Thread.each_caller_location do |cl|
        if frames_to_skip >= 1
          frames_to_skip -= 1
          next
        end

        if require_found
          if cl.base_label != "require"
            location = cl.path
            break
          end
        else
          if cl.base_label == "require"
            require_found = true
          end
        end
      end

      if location && File.file?(location) && !location.start_with?(Gem::BUNDLED_GEMS::LIBDIR)
        caller_gem = nil
        Gem.path.each do |path|
          if location =~ %r{#{path}/gems/([\w\-\.]+)}
            caller_gem = $1
            break
          end
        end
        if caller_gem
          msg += "\nAlso please contact the author of #{caller_gem} to request adding #{name} into its gemspec."
        end
      end
    else
      msg += " Install #{name} from RubyGems."
    end

    msg
  end

  def self.force_activate(gem)
    require "bundler"
    Bundler.reset!

    builder = Bundler::Dsl.new

    if Bundler::SharedHelpers.in_bundle?
      if Bundler.locked_gems
        Bundler.locked_gems.specs.each{|spec| builder.gem spec.name, spec.version.to_s }
      elsif Bundler.definition.gemfiles.size > 0
        Bundler.definition.gemfiles.each{|gemfile| builder.eval_gemfile(gemfile) }
      end
    end

    builder.gem gem

    definition = builder.to_definition(nil, true)
    definition.validate_runtime!

    begin
      orig_ui = Bundler.ui
      orig_no_lock = Bundler::Definition.no_lock

      ui = Bundler::UI::Shell.new
      ui.level = "silent"
      Bundler.ui = ui
      Bundler::Definition.no_lock = true

      Bundler::Runtime.new(nil, definition).setup
    rescue Bundler::GemNotFound
      warn "Failed to activate #{gem}, please install it with 'gem install #{gem}'"
    ensure
      Bundler.ui = orig_ui
      Bundler::Definition.no_lock = orig_no_lock
    end
  end
end

# for RubyGems without Bundler environment.
# If loading library is not part of the default gems and the bundled gems, warn it.
class LoadError
  def message # :nodoc:
    return super unless path

    name = path.tr("/", "-")
    if !defined?(Bundler) && Gem::BUNDLED_GEMS::SINCE[name] && !Gem::BUNDLED_GEMS::WARNED[name]
      warn name + Gem::BUNDLED_GEMS.build_message(name, :error), uplevel: Gem::BUNDLED_GEMS.uplevel
    end
    super
  end
end
