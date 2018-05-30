require 'delegate'
require 'uri'

class Gem::SpecificationPolicy < SimpleDelegator
  VALID_NAME_PATTERN = /\A[a-zA-Z0-9\.\-\_]+\z/ # :nodoc:

  VALID_URI_PATTERN = %r{\Ahttps?:\/\/([^\s:@]+:[^\s:@]*@)?[A-Za-z\d\-]+(\.[A-Za-z\d\-]+)+\.?(:\d{1,5})?([\/?]\S*)?\z}  # :nodoc:

  METADATA_LINK_KEYS = %w[
    bug_tracker_uri
    changelog_uri
    documentation_uri
    homepage_uri
    mailing_list_uri
    source_code_uri
    wiki_uri
  ] # :nodoc:

  ##
  # If set to true, run packaging-specific checks, as well.

  attr_accessor :packaging

  ##
  # Checks that the specification contains all required fields, and does a
  # very basic sanity check.
  #
  # Raises InvalidSpecificationException if the spec does not pass the
  # checks.

  def validate
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
    true
  end

  ##
  # Implementation for Specification#validate_metadata

  def validate_metadata
    unless Hash === metadata then
      raise Gem::InvalidSpecificationException,
            'metadata must be a hash'
    end

    metadata.each do |key, value|
      if !key.kind_of?(String) then
        raise Gem::InvalidSpecificationException,
              "metadata keys must be a String"
      end

      if key.size > 128 then
        raise Gem::InvalidSpecificationException,
              "metadata key too large (#{key.size} > 128)"
      end

      if !value.kind_of?(String) then
        raise Gem::InvalidSpecificationException,
              "metadata values must be a String"
      end

      if value.size > 1024 then
        raise Gem::InvalidSpecificationException,
              "metadata value too large (#{value.size} > 1024)"
      end

      if METADATA_LINK_KEYS.include? key then
        if value !~ VALID_URI_PATTERN then
          raise Gem::InvalidSpecificationException,
                "metadata['#{key}'] has invalid link: #{value.inspect}"
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
      if prev = seen[dep.type][dep.name] then
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

      overly_strict = dep.requirement.requirements.length == 1 &&
          dep.requirement.requirements.any? do |op, version|
            op == '~>' and
                not version.prerelease? and
                version.segments.length > 2 and
                version.segments.first != 0
          end

      if overly_strict then
        _, dep_version = dep.requirement.requirements.first

        base = dep_version.segments.first 2
        upper_bound = dep_version.segments.first(dep_version.segments.length - 1)
        upper_bound[-1] += 1

        warning_messages << <<-WARNING
pessimistic dependency on #{dep} may be overly strict
  if #{dep.name} is semantically versioned, use:
    add_#{dep.type}_dependency '#{dep.name}', '~> #{base.join '.'}', '>= #{dep_version}'
  if #{dep.name} is not semantically versioned, you can bypass this warning with:
    add_#{dep.type}_dependency '#{dep.name}', '>= #{dep_version}', '< #{upper_bound.join '.'}.a'
        WARNING
      end

      open_ended = dep.requirement.requirements.all? do |op, version|
        not version.prerelease? and (op == '>' or op == '>=')
      end

      if open_ended then
        op, dep_version = dep.requirement.requirements.first

        base = dep_version.segments.first 2

        bugfix = if op == '>' then
                   ", '> #{dep_version}'"
                 elsif op == '>=' and base != dep_version.segments then
                   ", '>= #{dep_version}'"
                 end

        warning_messages << <<-WARNING
open-ended dependency on #{dep} is not recommended
  if #{dep.name} is semantically versioned, use:
    add_#{dep.type}_dependency '#{dep.name}', '~> #{base.join '.'}'#{bugfix}
        WARNING
      end
    end
    if error_messages.any? then
      raise Gem::InvalidSpecificationException, error_messages.join
    end
    if warning_messages.any? then
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
    raise Gem::InvalidSpecificationException,
          "#{nil_attributes.join ', '} must not be nil"
  end

  def validate_rubygems_version
    return unless packaging
    return if rubygems_version == Gem::VERSION

    raise Gem::InvalidSpecificationException,
          "expected RubyGems version #{Gem::VERSION}, was #{rubygems_version}"
  end

  def validate_required_attributes
    Gem::Specification.required_attributes.each do |symbol|
      unless send symbol then
        raise Gem::InvalidSpecificationException,
              "missing value for attribute #{symbol}"
      end
    end
  end

  def validate_name
    if !name.is_a?(String) then
      raise Gem::InvalidSpecificationException,
            "invalid value for attribute name: \"#{name.inspect}\" must be a string"
    elsif name !~ /[a-zA-Z]/ then
      raise Gem::InvalidSpecificationException,
            "invalid value for attribute name: #{name.dump} must include at least one letter"
    elsif name !~ VALID_NAME_PATTERN then
      raise Gem::InvalidSpecificationException,
            "invalid value for attribute name: #{name.dump} can only include letters, numbers, dashes, and underscores"
    end
  end

  def validate_require_paths
    return unless raw_require_paths.empty?

    raise Gem::InvalidSpecificationException,
          'specification must have at least one require_path'
  end

  def validate_non_files
    return unless packaging
    non_files = files.reject {|x| File.file?(x) || File.symlink?(x)}

    unless non_files.empty? then
      raise Gem::InvalidSpecificationException,
            "[\"#{non_files.join "\", \""}\"] are not files"
    end
  end

  def validate_self_inclusion_in_files_list
    return unless files.include?(file_name)

    raise Gem::InvalidSpecificationException,
          "#{full_name} contains itself (#{file_name}), check your files list"
  end

  def validate_specification_version
    return if specification_version.is_a?(Integer)

    raise Gem::InvalidSpecificationException,
          'specification_version must be an Integer (did you mean version?)'
  end

  def validate_platform
    case platform
      when Gem::Platform, Gem::Platform::RUBY then # ok
      else
        raise Gem::InvalidSpecificationException,
              "invalid platform #{platform.inspect}, see Gem::Platform"
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

    unless Array === val and val.all? {|x| x.kind_of?(klass)} then
      raise(Gem::InvalidSpecificationException,
            "#{field} must be an Array of #{klass}")
    end
  end

  def validate_authors_field
    return unless authors.empty?

    raise Gem::InvalidSpecificationException,
          "authors may not be empty"
  end

  def validate_licenses
    licenses.each { |license|
      if license.length > 64 then
        raise Gem::InvalidSpecificationException,
              "each license must be 64 characters or less"
      end

      if !Gem::Licenses.match?(license) then
        suggestions = Gem::Licenses.suggestions(license)
        message = <<-warning
license value '#{license}' is invalid.  Use a license identifier from
http://spdx.org/licenses or '#{Gem::Licenses::NONSTANDARD}' for a nonstandard license.
        warning
        message += "Did you mean #{suggestions.map { |s| "'#{s}'"}.join(', ')}?\n" unless suggestions.nil?
        warning(message)
      end
    }

    warning <<-warning if licenses.empty?
licenses is empty, but is recommended.  Use a license identifier from
http://spdx.org/licenses or '#{Gem::Licenses::NONSTANDARD}' for a nonstandard license.
    warning
  end

  LAZY = '"FIxxxXME" or "TOxxxDO"'.gsub(/xxx/, '')
  LAZY_PATTERN = /FI XME|TO DO/x
  HOMEPAGE_URI_PATTERN = /\A[a-z][a-z\d+.-]*:/i

  def validate_lazy_metadata
    unless authors.grep(LAZY_PATTERN).empty? then
      raise Gem::InvalidSpecificationException, "#{LAZY} is not an author"
    end

    unless Array(email).grep(LAZY_PATTERN).empty? then
      raise Gem::InvalidSpecificationException, "#{LAZY} is not an email"
    end

    if description =~ LAZY_PATTERN then
      raise Gem::InvalidSpecificationException, "#{LAZY} is not a description"
    end

    if summary =~ LAZY_PATTERN then
      raise Gem::InvalidSpecificationException, "#{LAZY} is not a summary"
    end

    # Make sure a homepage is valid HTTP/HTTPS URI
    if homepage and not homepage.empty?
      begin
        homepage_uri = URI.parse(homepage)
        unless [URI::HTTP, URI::HTTPS].member? homepage_uri.class
          raise Gem::InvalidSpecificationException, "\"#{homepage}\" is not a valid HTTP URI"
        end
      rescue URI::InvalidURIError
        raise Gem::InvalidSpecificationException, "\"#{homepage}\" is not a valid HTTP URI"
      end
    end
  end

  def validate_values
    %w[author homepage summary files].each do |attribute|
      validate_attribute_present(attribute)
    end

    if description == summary then
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
end
