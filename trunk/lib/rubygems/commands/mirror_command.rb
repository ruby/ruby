require 'yaml'
require 'zlib'

require 'rubygems/command'
require 'open-uri'

class Gem::Commands::MirrorCommand < Gem::Command

  def initialize
    super 'mirror', 'Mirror a gem repository'
  end

  def description # :nodoc:
    <<-EOF
The mirror command uses the ~/.gemmirrorrc config file to mirror remote gem
repositories to a local path. The config file is a YAML document that looks
like this:

  ---
  - from: http://gems.example.com # source repository URI
    to: /path/to/mirror           # destination directory

Multiple sources and destinations may be specified.
    EOF
  end

  def execute
    config_file = File.join Gem.user_home, '.gemmirrorrc'

    raise "Config file #{config_file} not found" unless File.exist? config_file

    mirrors = YAML.load_file config_file

    raise "Invalid config file #{config_file}" unless mirrors.respond_to? :each

    mirrors.each do |mir|
      raise "mirror missing 'from' field" unless mir.has_key? 'from'
      raise "mirror missing 'to' field" unless mir.has_key? 'to'

      get_from = mir['from']
      save_to = File.expand_path mir['to']

      raise "Directory not found: #{save_to}" unless File.exist? save_to
      raise "Not a directory: #{save_to}" unless File.directory? save_to

      gems_dir = File.join save_to, "gems"

      if File.exist? gems_dir then
        raise "Not a directory: #{gems_dir}" unless File.directory? gems_dir
      else
        Dir.mkdir gems_dir
      end

      sourceindex_data = ''

      say "fetching: #{get_from}/Marshal.#{Gem.marshal_version}.Z"

      get_from = URI.parse get_from

      if get_from.scheme.nil? then
        get_from = get_from.to_s
      elsif get_from.scheme == 'file' then
        # check if specified URI contains a drive letter (file:/D:/Temp)
        get_from = get_from.to_s
        get_from = if get_from =~ /^file:.*[a-z]:/i then
                     get_from[6..-1]
                   else
                     get_from[5..-1]
                   end
      end

      open File.join(get_from.to_s, "Marshal.#{Gem.marshal_version}.Z"), "rb" do |y|
        sourceindex_data = Zlib::Inflate.inflate y.read
        open File.join(save_to, "Marshal.#{Gem.marshal_version}"), "wb" do |out|
          out.write sourceindex_data
        end
      end

      sourceindex = Marshal.load(sourceindex_data)

      progress = ui.progress_reporter sourceindex.size,
                                      "Fetching #{sourceindex.size} gems"
      sourceindex.each do |fullname, gem|
        gem_file = "#{fullname}.gem"
        gem_dest = File.join gems_dir, gem_file

        unless File.exist? gem_dest then
          begin
            open "#{get_from}/gems/#{gem_file}", "rb" do |g|
              contents = g.read
              open gem_dest, "wb" do |out|
                out.write contents
              end
            end
          rescue
            old_gf = gem_file
            gem_file = gem_file.downcase
            retry if old_gf != gem_file
            alert_error $!
          end
        end

        progress.updated gem_file
      end

      progress.done
    end
  end

end

