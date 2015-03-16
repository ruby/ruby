require 'English'
require 'rubygems/command'
require 'rubygems/version_option'
require 'rubygems/util'

class Gem::Commands::OpenCommand < Gem::Command

  include Gem::VersionOption

  def initialize
    super 'open', 'Open gem sources in editor'

    add_option('-e', '--editor EDITOR', String,
               "Opens gem sources in EDITOR") do |editor, options|
      options[:editor] = editor || get_env_editor
    end
  end

  def arguments # :nodoc:
    "GEMNAME     name of gem to open in editor"
  end

  def defaults_str # :nodoc:
    "-e #{get_env_editor}"
  end

  def description # :nodoc:
    <<-EOF
        The open command opens gem in editor and changes current path
        to gem's source directory. Editor can be specified with -e option,
        otherwise rubygems will look for editor in $EDITOR, $VISUAL and
        $GEM_EDITOR variables.
    EOF
  end

  def usage # :nodoc:
    "#{program_name} GEMNAME [-e EDITOR]"
  end

  def get_env_editor
    ENV['GEM_EDITOR'] ||
      ENV['VISUAL'] ||
      ENV['EDITOR'] ||
      'vi'
  end

  def execute
    @version = options[:version] || Gem::Requirement.default
    @editor  = options[:editor] || get_env_editor

    found = open_gem(get_one_gem_name)

    terminate_interaction 1 unless found
  end

  def open_gem name
    spec = spec_for name
    return false unless spec

    open_editor(spec.full_gem_path)
  end

  def open_editor path
    Dir.chdir(path) do
      system(*@editor.split(/\s+/) + [path])
    end
  end

  def spec_for name
    spec = Gem::Specification.find_all_by_name(name, @version).last

    return spec if spec

    say "Unable to find gem '#{name}'"
  end
end
