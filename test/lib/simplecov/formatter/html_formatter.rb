require 'erb'
require 'cgi'
require 'fileutils'
require 'digest/sha1'
require 'time'

class SimpleCov::Formatter::HTMLFormatter
  def format(result)
    Dir[File.join(File.dirname(__FILE__), 'html_formatter/public/*')].each do |path|
      FileUtils.cp_r(path, asset_output_path)
    end

    File.open(File.join(output_path, "index.html"), "w+") do |file|
      file.puts template('layout').result(binding)
    end
    puts output_message(result)
  end

  def output_message(result)
    "Coverage report generated for #{result.command_name} to #{output_path}. #{result.covered_lines} / #{result.total_lines} LOC (#{result.covered_percent.round(2)}%) covered."
  end

  private

  # Returns the an erb instance for the template of given name
  def template(name)
    ERB.new(File.read(File.join(File.dirname(__FILE__), 'html_formatter/views/', "#{name}.erb")))
  end

  def output_path
    SimpleCov.coverage_path
  end

  def asset_output_path
    return @asset_output_path if defined? @asset_output_path and @asset_output_path
    @asset_output_path = File.join(output_path, 'assets', SimpleCov::Formatter::HTMLFormatter::VERSION)
    FileUtils.mkdir_p(@asset_output_path)
    @asset_output_path
  end

  def assets_path(name)
    File.join('./assets', SimpleCov::Formatter::HTMLFormatter::VERSION, name)
  end

  # Returns the html for the given source_file
  def formatted_source_file(source_file)
    template('source_file').result(binding)
  end

  # Returns a table containing the given source files
  def formatted_file_list(title, source_files)
    title_id = title.gsub(/^[^a-zA-Z]+/, '').gsub(/[^a-zA-Z0-9\-\_]/, '')
    title_id # Ruby will give a warning when we do not use this except via the binding :( FIXME
    template('file_list').result(binding)
  end

  def coverage_css_class(covered_percent)
    if covered_percent > 90
      'green'
    elsif covered_percent > 80
      'yellow'
    else
      'red'
    end
  end

  def strength_css_class(covered_strength)
    if covered_strength > 1
      'green'
    elsif covered_strength == 1
      'yellow'
    else
      'red'
    end
  end

  # Return a (kind of) unique id for the source file given. Uses SHA1 on path for the id
  def id(source_file)
    Digest::SHA1.hexdigest(source_file.filename)
  end

  def timeago(time)
    "<abbr class=\"timeago\" title=\"#{time.iso8601}\">#{time.iso8601}</abbr>"
  end

  def shortened_filename(source_file)
    source_file.filename.gsub(SimpleCov.root, '.').gsub(/^\.\//, '')
  end

  def link_to_source_file(source_file)
    %Q(<a href="##{id source_file}" class="src_link" title="#{shortened_filename source_file}">#{shortened_filename source_file}</a>)
  end
end

$LOAD_PATH.unshift(File.join(File.dirname(__FILE__)))
require 'html_formatter/version'
