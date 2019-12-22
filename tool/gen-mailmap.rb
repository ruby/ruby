#!/usr/bin/env ruby

require "open-uri"
require "yaml"

EMAIL_YML_URL = "https://cdn.jsdelivr.net/gh/ruby/ruby-commit-hook/config/email.yml"

email_yml = URI(EMAIL_YML_URL).read.sub(/\A(?:#.*\n)+/, "").gsub(/^# +(.+)$/) { $1 + ": []" }

email = YAML.load(email_yml)
YAML.load(DATA.read).each do |name, mails|
  email[name] ||= []
  email[name] |= mails
end

open(File.join(__dir__, "../.mailmap"), "w") do |f|
  email.each do |name, mails|
    canonical = "#{ name }@ruby-lang.org"
    mails.delete(canonical)
    svn = "#{ name }@b2dd03c8-39d4-4d8f-98ff-823fe69b080e"
    ((mails | [canonical]) + [svn]).each do |mail|
      f.puts "#{ name } <#{ canonical }> <#{ mail }>"
    end
  end
end

puts "You'll see canonical names (SVN account names) by the following commands:"
puts
puts "  git shortlog -ce"
puts "  git log --pretty=format:'%cN <%cE>'"
puts "  git log --use-mailmap --pretty=full"

__END__
git:
- svn@b2dd03c8-39d4-4d8f-98ff-823fe69b080e
- "(no author)@b2dd03c8-39d4-4d8f-98ff-823fe69b080e"
kazu:
- znz@users.noreply.github.com
marcandre:
- github@marc-andre.ca
mrkn:
- mrkn@users.noreply.github.com
- muraken@b2dd03c8-39d4-4d8f-98ff-823fe69b080e
naruse:
- nurse@users.noreply.github.com
tenderlove:
- tenderlove@github.com
