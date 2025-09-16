# frozen_string_literal: true

RSpec.describe "bundle commands" do
  it "expects all commands to have all options and subcommands documented" do
    check_commands!(Bundler::CLI)

    Bundler::CLI.subcommand_classes.each_value do |klass|
      check_commands!(klass)
    end
  end

  private

  def check_commands!(command_class)
    command_class.commands.each do |command_name, command|
      if command.is_a?(Bundler::Thor::HiddenCommand)
        man_page = man_page(command_name)
        expect(man_page).not_to exist
        expect(main_man_page.read).not_to include("bundle #{command_name}")
      elsif command_class == Bundler::CLI
        man_page = man_page(command_name)
        expect(man_page).to exist

        check_options!(command, man_page)
      else
        man_page = man_page(command.ancestor_name)
        expect(man_page).to exist

        check_options!(command, man_page)
        check_subcommand!(command_name, man_page)
      end
    end
  end

  def check_options!(command, man_page)
    command.options.each do |_, option|
      check_option!(option, man_page)
    end
  end

  def check_option!(option, man_page)
    man_page_content = man_page.read

    aliases = option.aliases
    formatted_aliases = aliases.sort.map {|name| "`#{name}`" }.join(", ") if aliases

    help = if option.type == :boolean
      "* #{append_aliases("`#{option.switch_name}`", formatted_aliases)}:"
    elsif option.enum
      formatted_aliases = "`#{option.switch_name}`" if aliases.empty? && option.lazy_default
      "* #{prepend_aliases(option.enum.sort.map {|enum| "`#{option.switch_name}=#{enum}`" }.join(", "), formatted_aliases)}:"
    else
      names = [option.switch_name, *aliases]
      value =
        case option.type
        when :array then "<list>"
        when :numeric then "<number>"
        else option.name.upcase
        end

      value = option.type != :numeric && option.lazy_default ? "[=#{value}]" : "=#{value}"

      "* #{names.map {|name| "`#{name}#{value}`" }.join(", ")}:"
    end

    if option.banner.include?("(removed)")
      expect(man_page_content).not_to include(help)
    else
      expect(man_page_content).to include(help)
    end
  end

  def check_subcommand!(name, man_page)
    expect(man_page.read).to match(name)
  end

  def append_aliases(text, aliases)
    return text if aliases.empty?

    "#{text}, #{aliases}"
  end

  def prepend_aliases(text, aliases)
    return text if aliases.empty?

    "#{aliases}, #{text}"
  end

  def man_page_content(command_name)
    man_page(command_name).read
  end

  def man_page(command_name)
    source_root.join("lib/bundler/man/bundle-#{command_name}.1.ronn")
  end

  def main_man_page
    source_root.join("lib/bundler/man/bundle.1.ronn")
  end
end
