require 'delegate'
require 'uri'
require 'rubygems/user_interaction'

class Gem::SpecificationPolicy < SimpleDelegator

  include Gem::UserInteraction

  VALID_NAME_PATTERN = /\A[a-zA-Z0-9\.\-\_]+\z/.freeze # :nodoc:

  SPECIAL_CHARACTERS = /\A[#{Regexp.escape('.-_')}]+/.freeze # :nodoc:

  VALID_URI_PATTERN = %r{\Ahttps?:\/\/([^\s:@]+:[^\s:@]*@)?[A-Za-z\d\-]+(\.[A-Za-z\d\-]+)+\.?(:\d{1,5})?([\/?]\S*)?\z}.freeze  # :nodoc:

  METADATA_LINK_KEYS = %w[
    bug_tracker_uri
    changelog_uri
    documentation_uri
    homepage_uri
    mailing_list_uri
    source_code_uri
    wiki_uri
  ].freeze # :nodoc:

  def initialize(specification)
    @warnings = 0

    super(specification)
  end

  ##
  # If set to true, run packaging-specific checks, as well.

  attr_accessor :packaging

  ##
  # Checks that the specification contains all required fields, and does a
  # very basic sanity check.
  #
  # Raises InvalidSpecificationException if the spec does not pass the
  # checks.

  def validate(strict = false)
    validate_nil_attributes

    validate_rubygems_version

    validate_required_attributes

    validate_name

    validate_require_paths

    keep_only_files_and_directories

    validate_non_files

    validate_self_inclusion_in_files_list

    validate_specification_version

    validate_platform

    validate_array_attributes

    validate_authors_field

    validate_metadata

    validate_licenses

    validate_permissions

    validate_lazy_metadata

    validate_values

    validate_dependencies

    if @warnings > 0
      if strict
        error "specification has warnings"
      else
        alert_warning help_text
      end
    end

    true
  end

  ##
  # Implementation for Specification#validate_metadata

  def validate_metadata
    unless Hash === metadata
      error 'metadata must be a hash'
    end

    metadata.each do |key, value|
      if !key.kind_of?(String)
        error "metadata keys must be a String"
      end

      if key.size > 128
        error "metadata key too large (#{key.size} > 128)"
      end

      if !value.kind_of?(String)
        error "metadata values must be a String"
      end

      if value.size > 1024
        error "metadata value too large (#{value.size} > 1024)"
      end

      if METADATA_LINK_KEYS.include? key
        if value !~ VALID_URI_PATTERN
          error "metadata['#{key}'] has invalid link: #{value.inspect}"
        end
      end
    end
  end

  ##
  # Implementation for Specification#validate_dependencies

  def validate_dependencies # :nodoc:
    # NOTE: see REFACTOR note in Gem::Dependency about types - this might be brittle
    seen = Gem::Dependency::TYPES.inject({}) { |types, type| types.merge({ type => {}}) }

    error_messages = []
    warning_messages = []
    dependencies.each do |dep|
      if prev = seen[dep.type][dep.name]
        error_messages << <<-MESSAGE
duplicate dependency on #{dep}, (#{prev.requirement}) use:
    add_#{dep.type}_dependency '#{dep.name}', '#{dep.requirement}', '#{prev.requirement}'
        MESSAGE
      end

      seen[dep.type][dep.name] = dep

      prerelease_dep = dep.requirements_list.any? do |req|
        Gem::Requirement.new(req).prerelease?
      end

      warning_messages << "prerelease dependency on #{dep} is not recommended" if
          prerelease_dep && !version.prerelease?

      open_ended = dep.requirement.requirements.all? do |op, version|
        not version.prerelease? and (op == '>' or op == '>=')
      end

      if open_ended
        op, dep_version = dep.requirement.requirements.first

        segments = dep_version.segments

        base = segments.first 2

        recommendation = if (op == '>' || op == '>=') && segments == [0]
                           "  use a bounded requirement, such as '~> x.y'"
                         else
                           bugfix = if op == '>'
                                      ", '> #{dep_version}'"
                                    elsif op == '>=' and base != segments
                                      ", '>= #{dep_version}'"
                                    end

                           "  if #{dep.name} is semantically versioned, use:\n" \
                           "    add_#{dep.type}_dependency '#{dep.name}', '~> #{base.join '.'}'#{bugfix}"
                         end

        warning_messages << ["open-ended dependency on #{dep} is not recommended", recommendation].join("\n") + "\n"
      end
    end
    if error_messages.any?
      error error_messages.join
    end
    if warning_messages.any?
      warning_messages.each { |warning_message| warning warning_message }
    end
  end

  ##
  # Issues a warning for each file to be packaged which is world-readable.
  #
  # Implementation for Specification#validate_permissions

  def validate_permissions
    return if Gem.win_platform?

    files.each do |file|
      next unless File.file?(file)
      next if File.stat(file).mode & 0444 == 0444
      warning "#{file} is not world-readable"
    end

    executables.each do |name|
      exec = File.join bindir, name
      next unless File.file?(exec)
      next if File.stat(exec).executable?
      warning "#{exec} is not executable"
    end
  end

  private

  def validate_nil_attributes
    nil_attributes = Gem::Specification.non_nil_attributes.select do |attrname|
      __getobj__.instance_variable_get("@#{attrname}").nil?
    end
    return if nil_attributes.empty?
    error "#{nil_attributes.join ', '} must not be nil"
  end

  def validate_rubygems_version
    return unless packaging
    return if rubygems_version == Gem::VERSION

    error "expected RubyGems version #{Gem::VERSION}, was #{rubygems_version}"
  end

  def validate_required_attributes
    Gem::Specification.required_attributes.each do |symbol|
      unless send symbol
        error "missing value for attribute #{symbol}"
      end
    end
  end

  def validate_name
    if !name.is_a?(String)
      error "invalid value for attribute name: \"#{name.inspect}\" must be a string"
    elsif name !~ /[a-zA-Z]/
      error "invalid value for attribute name: #{name.dump} must include at least one letter"
    elsif name !~ VALID_NAME_PATTERN
      error "invalid value for attribute name: #{name.dump} can only include letters, numbers, dashes, and underscores"
    elsif name =~ SPECIAL_CHARACTERS
      error "invalid value for attribute name: #{name.dump} can not begin with a period, dash, or underscore"
    end
  end

  def validate_require_paths
    return unless raw_require_paths.empty?

    error 'specification must have at least one require_path'
  end

  def validate_non_files
    return unless packaging
    non_files = files.reject {|x| File.file?(x) || File.symlink?(x)}

    unless non_files.empty?
      error "[\"#{non_files.join "\", \""}\"] are not files"
    end
  end

  def validate_self_inclusion_in_files_list
    return unless files.include?(file_name)

    error "#{full_name} contains itself (#{file_name}), check your files list"
  end

  def validate_specification_version
    return if specification_version.is_a?(Integer)

    error 'specification_version must be an Integer (did you mean version?)'
  end

  def validate_platform
    case platform
    when Gem::Platform, Gem::Platform::RUBY  # ok
    else
      error "invalid platform #{platform.inspect}, see Gem::Platform"
    end
  end

  def validate_array_attributes
    Gem::Specification.array_attributes.each do |field|
      validate_array_attribute(field)
    end
  end

  def validate_array_attribute(field)
    val = self.send(field)
    klass = case field
            when :dependencies then
              Gem::Dependency
            else
              String
            end

    unless Array === val and val.all? {|x| x.kind_of?(klass)}
      raise(Gem::InvalidSpecificationException,
            "#{field} must be an Array of #{klass}")
    end
  end

  def validate_authors_field
    return unless authors.empty?

    error "authors may not be empty"
  end

  def validate_licenses
    licenses.each do |license|
      if license.length > 64
        error "each license must be 64 characters or less"
      end

      if !Gem::Licenses.match?(license)
        suggestions = Gem::Licenses.suggestions(license)
        message = <<-warning
license value '#{license}' is invalid.  Use a license identifier from
http://spdx.org/licenses or '#{Gem::Licenses::NONSTANDARD}' for a nonstandard license.
        warning
        message += "Did you mean #{suggestions.map { |s| "'#{s}'"}.join(', ')}?\n" unless suggestions.nil?
        warning(message)
      end
    end

    warning <<-warning if licenses.empty?
licenses is empty, but is recommended.  Use a license identifier from
http://spdx.org/licenses or '#{Gem::Licenses::NONSTANDARD}' for a nonstandard license.
    warning
  end

  LAZY = '"FIxxxXME" or "TOxxxDO"'.gsub(/xxx/, '')
  LAZY_PATTERN = /FI XME|TO DO/x.freeze
  HOMEPAGE_URI_PATTERN = /\A[a-z][a-z\d+.-]*:/i.freeze

  def validate_lazy_metadata
    unless authors.grep(LAZY_PATTERN).empty?
      error "#{LAZY} is not an author"
    end

    unless Array(email).grep(LAZY_PATTERN).empty?
      error "#{LAZY} is not an email"
    end

    if description =~ LAZY_PATTERN
      error "#{LAZY} is not a description"
    end

    if summary =~ LAZY_PATTERN
      error "#{LAZY} is not a summary"
    end

    # Make sure a homepage is valid HTTP/HTTPS URI
    if homepage and not homepage.empty?
      begin
        homepage_uri = URI.parse(homepage)
        unless [URI::HTTP, URI::HTTPS].member? homepage_uri.class
          error "\"#{homepage}\" is not a valid HTTP URI"
        end
      rescue URI::InvalidURIError
        error "\"#{homepage}\" is not a valid HTTP URI"
      end
    end
  end

  def validate_values
    %w[author homepage summary files].each do |attribute|
      validate_attribute_present(attribute)
    end

    if description == summary
      warning "description and summary are identical"
    end

    # TODO: raise at some given date
    warning "deprecated autorequire specified" if autorequire

    executables.each do |executable|
      validate_shebang_line_in(executable)
    end

    files.select { |f| File.symlink?(f) }.each do |file|
      warning "#{file} is a symlink, which is not supported on all platforms"
    end
  end

  def validate_attribute_present(attribute)
    value = self.send attribute
    warning("no #{attribute} specified") if value.nil? || value.empty?
  end

  def validate_shebang_line_in(executable)
    executable_path = File.join(bindir, executable)
    return if File.read(executable_path, 2) == '#!'

    warning "#{executable_path} is missing #! line"
  end

  def warning(statement) # :nodoc:
    @warnings += 1

    alert_warning statement
  end

  def error(statement) # :nodoc:
    raise Gem::InvalidSpecificationException, statement
  ensure
    alert_warning help_text
  end

  def help_text # :nodoc:
    "See http://guides.rubygems.org/specification-reference/ for help"
  end

end
