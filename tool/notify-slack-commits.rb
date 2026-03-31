#!/usr/bin/env ruby

require "net/https"
require "open3"
require "json"
require "digest/md5"

SLACK_WEBHOOK_URLS = [
  ENV.fetch("SLACK_WEBHOOK_URL_ALERTS").chomp, # ruby-lang#alerts
  ENV.fetch("SLACK_WEBHOOK_URL_COMMITS").chomp, # ruby-lang#commits
  ENV.fetch("SLACK_WEBHOOK_URL_RUBY_JP").chomp, # ruby-jp#ruby-commits
]
GRAVATAR_OVERRIDES = {
  "nagachika@b2dd03c8-39d4-4d8f-98ff-823fe69b080e" => "https://avatars0.githubusercontent.com/u/21976",
  "noreply@github.com" => "https://avatars1.githubusercontent.com/u/9919",
  "nurse@users.noreply.github.com" => "https://avatars1.githubusercontent.com/u/13423",
  "svn-admin@ruby-lang.org" => "https://avatars1.githubusercontent.com/u/29403229",
  "svn@b2dd03c8-39d4-4d8f-98ff-823fe69b080e" => "https://avatars1.githubusercontent.com/u/29403229",
  "usa@b2dd03c8-39d4-4d8f-98ff-823fe69b080e" => "https://avatars2.githubusercontent.com/u/17790",
  "usa@ruby-lang.org" => "https://avatars2.githubusercontent.com/u/17790",
  "yui-knk@ruby-lang.org" => "https://avatars0.githubusercontent.com/u/5356517",
  "znz@users.noreply.github.com" => "https://avatars3.githubusercontent.com/u/11857",
}

def escape(s)
  s.gsub(/[&<>]/, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;")
end

ARGV.each_slice(3) do |oldrev, newrev, refname|
  out, = Open3.capture2("git", "rev-parse", "--symbolic", "--abbrev-ref", refname)
  branch = out.strip

  out, = Open3.capture2("git", "log", "--pretty=format:%H\n%h\n%cn\n%ce\n%ct\n%B", "--abbrev=10", "-z", "#{oldrev}..#{newrev}")

  attachments = []
  out.split("\0").reverse_each do |s|
    sha, sha_abbr, committer, committeremail, committertime, body = s.split("\n", 6)
    subject, body = body.split("\n", 2)

    # Append notes content to `body` if it's notes
    if refname.match(%r[\Arefs/notes/\w+\z])
      # `--diff-filter=AM -M` to exclude rename by git's directory optimization
      object = IO.popen(["git", "diff", "--diff-filter=AM", "-M", "--name-only", "#{sha}^..#{sha}"], &:read).chomp
      if md = object.match(/\A(?<prefix>\h{2})\/?(?<rest>\h{38})\z/)
        body = [body, IO.popen(["git", "notes", "show", md[:prefix] + md[:rest]], &:read)].join
      end
    end

    gravatar = GRAVATAR_OVERRIDES.fetch(committeremail) do
      "https://www.gravatar.com/avatar/#{ Digest::MD5.hexdigest(committeremail.downcase) }"
    end

    attachments << {
      title: "#{ sha_abbr } (#{ branch }): #{ escape(subject) }",
      title_link: "https://github.com/ruby/ruby/commit/#{ sha }",
      text: escape((body || "").strip),
      footer: committer,
      footer_icon: gravatar,
      ts: committertime.to_i,
      color: '#24282D',
    }
  end

  # 100 attachments cannot be exceeded. 20 is recommended. https://api.slack.com/docs/message-attachments
  attachments.each_slice(20).each do |attachments_group|
    payload = { attachments: attachments_group }

    #Net::HTTP.post(
    #  URI.parse(SLACK_WEBHOOK_URL),
    #  JSON.generate(payload),
    #  "Content-Type" => "application/json"
    #)
    responses = SLACK_WEBHOOK_URLS.map do |url|
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.start do
        req = Net::HTTP::Post.new(uri.path)
        req.set_form_data(payload: payload.to_json)
        http.request(req)
      end
    end

    results = responses.map { |resp| "#{resp.code} (#{resp.body})" }.join(', ')
    puts "#{results} -- #{payload.to_json}"
  end
end
