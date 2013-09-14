require 'rubygems/command'

class Gem::Commands::HelpCommand < Gem::Command

  # :stopdoc:
  EXAMPLES = <<-EOF
Some examples of 'gem' usage.

* Install 'rake', either from local directory or remote server:

    gem install rake

* Install 'rake', only from remote server:

    gem install rake --remote

* Install 'rake', but only version 0.3.1, even if dependencies
  are not met, and into a user-specific directory:

    gem install rake --version 0.3.1 --force --user-install

* List local gems whose name begins with 'D':

    gem list D

* List local and remote gems whose name contains 'log':

    gem search log --both

* List only remote gems whose name contains 'log':

    gem search log --remote

* Uninstall 'rake':

    gem uninstall rake

* Create a gem:

    See http://guides.rubygems.org/make-your-own-gem/

* See information about RubyGems:

    gem environment

* Update all gems on your system:

    gem update

* Update your local version of RubyGems

    gem update --system
  EOF

  PLATFORMS = <<-'EOF'
RubyGems platforms are composed of three parts, a CPU, an OS, and a
version.  These values are taken from values in rbconfig.rb.  You can view
your current platform by running `gem environment`.

RubyGems matches platforms as follows:

  * The CPU must match exactly unless one of the platforms has
    "universal" as the CPU or the local CPU starts with "arm" and the gem's
    CPU is exactly "arm" (for gems that support generic ARM architecture).
  * The OS must match exactly.
  * The versions must match exactly unless one of the versions is nil.

For commands that install, uninstall and list gems, you can override what
RubyGems thinks your platform is with the --platform option.  The platform
you pass must match "#{cpu}-#{os}" or "#{cpu}-#{os}-#{version}".  On mswin
platforms, the version is the compiler version, not the OS version.  (Ruby
compiled with VC6 uses "60" as the compiler version, VC8 uses "80".)

For the ARM architecture, gems with a platform of "arm-linux" should run on a
reasonable set of ARM CPUs and not depend on instructions present on a limited
subset of the architecture.  For example, the binary should run on platforms
armv5, armv6hf, armv6l, armv7, etc.  If you use the "arm-linux" platform
please test your gem on a variety of ARM hardware before release to ensure it
functions correctly.

Example platforms:

  x86-freebsd        # Any FreeBSD version on an x86 CPU
  universal-darwin-8 # Darwin 8 only gems that run on any CPU
  x86-mswin32-80     # Windows gems compiled with VC8
  armv7-linux        # Gem complied for an ARMv7 CPU running linux
  arm-linux          # Gem compiled for any ARM CPU running linux

When building platform gems, set the platform in the gem specification to
Gem::Platform::CURRENT.  This will correctly mark the gem with your ruby's
platform.
  EOF
  # :startdoc:

  def initialize
    super 'help', "Provide help on the 'gem' command"

    @command_manager = Gem::CommandManager.instance
  end

  def arguments # :nodoc:
    args = <<-EOF
      commands      List all 'gem' commands
      examples      Show examples of 'gem' usage
      <command>     Show specific help for <command>
    EOF
    return args.gsub(/^\s+/, '')
  end

  def usage # :nodoc:
    "#{program_name} ARGUMENT"
  end

  def execute
    arg = options[:args][0]

    if begins? "commands", arg then
      show_commands

    elsif begins? "options", arg then
      say Gem::Command::HELP

    elsif begins? "examples", arg then
      say EXAMPLES

    elsif begins? "platforms", arg then
      say PLATFORMS

    elsif options[:help] then
      show_help

    elsif arg then
      show_command_help arg

    else
      say Gem::Command::HELP
    end
  end

  def show_commands # :nodoc:
    out = []
    out << "GEM commands are:"
    out << nil

    margin_width = 4

    desc_width = @command_manager.command_names.map { |n| n.size }.max + 4

    summary_width = 80 - margin_width - desc_width
    wrap_indent = ' ' * (margin_width + desc_width)
    format = "#{' ' * margin_width}%-#{desc_width}s%s"

    @command_manager.command_names.each do |cmd_name|
      command = @command_manager[cmd_name]

      summary =
        if command then
          command.summary
        else
          "[No command found for #{cmd_name}]"
        end

      summary = wrap(summary, summary_width).split "\n"
      out << sprintf(format, cmd_name, summary.shift)
      until summary.empty? do
        out << "#{wrap_indent}#{summary.shift}"
      end
    end

    out << nil
    out << "For help on a particular command, use 'gem help COMMAND'."
    out << nil
    out << "Commands may be abbreviated, so long as they are unambiguous."
    out << "e.g. 'gem i rake' is short for 'gem install rake'."

    say out.join("\n")
  end

  def show_command_help command_name # :nodoc:
    command_name = command_name.downcase

    possibilities = @command_manager.find_command_possibilities command_name

    if possibilities.size == 1 then
      command = @command_manager[possibilities.first]
      command.invoke("--help")
    elsif possibilities.size > 1 then
      alert_warning "Ambiguous command #{command_name} (#{possibilities.join(', ')})"
    else
      alert_warning "Unknown command #{command_name}.  Try: gem help commands"
    end
  end

  def show_help # :nodoc:
    command = @command_manager[options[:help]]
    if command then
      # help with provided command
      command.invoke("--help")
    else
      alert_error "Unknown command #{options[:help]}.  Try 'gem help commands'"
    end
  end

end

