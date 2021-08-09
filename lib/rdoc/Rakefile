$:.unshift File.expand_path 'lib'
require 'rdoc/task'
require 'bundler/gem_tasks'
require 'rake/testtask'

task :docs    => :generate
task :test    => [:normal_test, :rubygems_test]

PARSER_FILES = %w[
  lib/rdoc/rd/block_parser.ry
  lib/rdoc/rd/inline_parser.ry
  lib/rdoc/markdown.kpeg
  lib/rdoc/markdown/literals.kpeg
]

$rdoc_rakefile = true

task :default => :test

RDoc::Task.new do |doc|
  doc.main = 'README.rdoc'
  doc.title = "rdoc #{RDoc::VERSION} Documentation"
  doc.rdoc_dir = 'html'
  doc.rdoc_files = FileList.new %w[lib/**/*.rb *.rdoc] - PARSER_FILES
end

task ghpages: :rdoc do
  `git checkout gh-pages`
  require "fileutils"
  FileUtils.rm_rf "/tmp/html"
  FileUtils.mv "html", "/tmp"
  FileUtils.rm_rf "*"
  FileUtils.cp_r Dir.glob("/tmp/html/*"), "."
end

Rake::TestTask.new(:normal_test) do |t|
  t.libs << "test/rdoc"
  t.verbose = true
  t.deps = :generate
  t.test_files = FileList["test/**/test_*.rb"].exclude("test/rdoc/test_rdoc_rubygems_hook.rb")
end

Rake::TestTask.new(:rubygems_test) do |t|
  t.libs << "test/rdoc"
  t.verbose = true
  t.deps = :generate
  t.pattern = "test/rdoc/test_rdoc_rubygems_hook.rb"
end

path = "pkg/#{Bundler::GemHelper.gemspec.full_name}"

package_parser_files = PARSER_FILES.map do |parser_file|
  name = File.basename(parser_file, File.extname(parser_file))
  _path = File.dirname(parser_file)
  package_parser_file = "#{path}/#{name}.rb"
  parsed_file = "#{_path}/#{name}.rb"

  file package_parser_file => parsed_file # ensure copy runs before racc

  package_parser_file
end

parsed_files = PARSER_FILES.map do |parser_file|
  ext = File.extname(parser_file)
  parsed_file = "#{parser_file.chomp(ext)}.rb"

  file parsed_file => parser_file do |t|
    puts "Generating #{parsed_file}..."
    case ext
    when '.ry' # need racc
      racc = Gem.bin_path 'racc', 'racc'
      rb_file = parser_file.gsub(/\.ry\z/, ".rb")
      ruby "#{racc} -l -o #{rb_file} #{parser_file}"
      open(rb_file, 'r+') do |f|
        newtext = "# frozen_string_literal: true\n#{f.read}"
        f.rewind
        f.write newtext
      end
    when '.kpeg' # need kpeg
      kpeg = Gem.bin_path 'kpeg', 'kpeg'
      rb_file = parser_file.gsub(/\.kpeg\z/, ".rb")
      ruby "#{kpeg} -fsv -o #{rb_file} #{parser_file}"
    end
  end

  parsed_file
end

task "#{path}.gem" => package_parser_files
desc "Generate all files used racc and kpeg"
task :generate => parsed_files

begin
  require 'rubocop/rake_task'
rescue LoadError
else
  RuboCop::RakeTask.new(:rubocop) do |t|
    t.options = [*parsed_files]
  end
  task :build => [:generate, "rubocop:auto_correct"]
end
