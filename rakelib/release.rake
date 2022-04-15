release_task = Rake.application["release"]
release_task.prerequisites.delete("build")
release_task.prerequisites.delete("release:rubygem_push")
release_task_comment = release_task.comment
if release_task_comment
  release_task.clear_comments
  release_task.comment = release_task_comment.gsub(/ and build.*$/, "")
end

desc "Push built gems"
task "push" do
  require "open-uri"
  helper = Bundler::GemHelper.instance
  gemspec = helper.gemspec
  name = gemspec.name
  version = gemspec.version.to_s
  pkg_dir = "pkg"
  mkdir_p(pkg_dir)
  ["", "-java"].each do |type|
    base_url = "https://github.com/ruby/#{name}/releases/download"
    url = URI("#{base_url}/v#{version}/#{name}-#{version}#{type}.gem")
    path = "#{pkg_dir}/#{File.basename(url.path)}"
    url.open do |input|
      File.open(path, "wb") do |output|
        IO.copy_stream(input, output)
      end
      helper.__send__(:rubygem_push, path)
    end
  end
end
