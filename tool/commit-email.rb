#!/usr/bin/env ruby

require "optparse"
require "nkf"
require "shellwords"

CommitEmailInfo = Struct.new(
  :author,
  :author_email,
  :revision,
  :entire_sha256,
  :date,
  :log,
  :branch,
  :diffs,
  :added_files, :deleted_files, :updated_files,
  :added_dirs, :deleted_dirs, :updated_dirs,
)

class GitInfoBuilder
  GitCommandFailure = Class.new(RuntimeError)

  def initialize(repo_path)
    @repo_path = repo_path
  end

  def build(oldrev, newrev, refname)
    diffs = build_diffs(oldrev, newrev)

    info = CommitEmailInfo.new
    info.author = git_show(newrev, format: '%an')
    info.author_email = normalize_email(git_show(newrev, format: '%aE'))
    info.revision = newrev[0...10]
    info.entire_sha256 = newrev
    info.date = Time.at(Integer(git_show(newrev, format: '%at')))
    info.log = git_show(newrev, format: '%B')
    info.branch = git('rev-parse', '--symbolic', '--abbrev-ref', refname).strip
    info.diffs = diffs
    info.added_files = find_files(diffs, status: :added)
    info.deleted_files = find_files(diffs, status: :deleted)
    info.updated_files = find_files(diffs, status: :modified)
    info.added_dirs = [] # git does not deal with directory
    info.deleted_dirs = [] # git does not deal with directory
    info.updated_dirs = [] # git does not deal with directory
    info
  end

  private

  # Force git-svn email address to @ruby-lang.org to avoid email bounce by invalid email address.
  def normalize_email(email)
    if email.match(/\A[^@]+@\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/) # git-svn
      svn_user, _ = email.split('@', 2)
      "#{svn_user}@ruby-lang.org"
    else
      email
    end
  end

  def find_files(diffs, status:)
    files = []
    diffs.each do |path, values|
      if values.keys.first == status
        files << path
      end
    end
    files
  end

  # SVN version:
  # {
  #   "filename" => {
  #     "[modified|added|deleted|copied|property_changed]" => {
  #       type: "[modified|added|deleted|copied|property_changed]",
  #       body: "diff body", # not implemented because not used
  #       added: Integer,
  #       deleted: Integer,
  #     }
  #   }
  # }
  def build_diffs(oldrev, newrev)
    diffs = {}

    numstats = git('diff', '--numstat', oldrev, newrev).lines.map { |l| l.strip.split("\t", 3) }
    git('diff', '--name-status', oldrev, newrev).each_line do |line|
      status, path, _newpath = line.strip.split("\t", 3)
      diff = build_diff(path, numstats)

      case status
      when 'A'
        diffs[path] = { added: { type: :added, **diff } }
      when 'M'
        diffs[path] = { modified: { type: :modified, **diff } }
      when 'C'
        diffs[path] = { copied: { type: :copied, **diff } }
      when 'D'
        diffs[path] = { deleted: { type: :deleted, **diff } }
      when /\AR/ # R100 (which does not exist in git.ruby-lang.org's git 2.1.4)
        # TODO: implement something
      else
        $stderr.puts "unexpected git diff status: #{status}"
      end
    end

    diffs
  end

  def build_diff(path, numstats)
    diff = { added: 0, deleted: 0 } # :body not implemented because not used
    line = numstats.find { |(_added, _deleted, file, *)| file == path }
    return diff if line.nil?

    added, deleted, _ = line
    if added
      diff[:added] = Integer(added)
    end
    if deleted
      diff[:deleted] = Integer(deleted)
    end
    diff
  end

  def git_show(revision, format:)
    git('show', '--no-show-signature', "--pretty=#{format}", '--no-patch', revision).strip
  end

  def git(*args)
    command = ['git', '-C', @repo_path, *args]
    output = with_gitenv { IO.popen(command, external_encoding: 'UTF-8', &:read) }
    unless $?.success?
      raise GitCommandFailure, "failed to execute '#{command.join(' ')}':\n#{output}"
    end
    output
  end

  def with_gitenv
    orig = ENV.to_h.dup
    begin
      ENV.delete('GIT_DIR')
      yield
    ensure
      ENV.replace(orig)
    end
  end
end

CommitEmailOptions = Struct.new(:error_to, :viewer_uri)

CommitEmail = Module.new
class << CommitEmail
  SENDMAIL = ENV.fetch('SENDMAIL', '/usr/sbin/sendmail')
  private_constant :SENDMAIL

  def parse(args)
    options = CommitEmailOptions.new

    opts = OptionParser.new do |opts|
      opts.separator('')

      opts.on('-e', '--error-to [TO]',
              'Add [TO] to to address when error is occurred') do |to|
        options.error_to = to
      end

      opts.on('--viewer-uri [URI]',
              'Use [URI] as URI of revision viewer') do |uri|
        options.viewer_uri = uri
      end

      opts.on_tail('--help', 'Show this message') do
        puts opts
        exit
      end
    end

    return opts.parse(args), options
  end

  def main(repo_path, to, rest)
    args, options = parse(rest)

    infos = args.each_slice(3).flat_map do |oldrev, newrev, refname|
      revisions = IO.popen(['git', 'log', '--no-show-signature', '--reverse', '--pretty=%H', "#{oldrev}^..#{newrev}"], &:read).lines.map(&:strip)
      revisions[0..-2].zip(revisions[1..-1]).map do |old, new|
        GitInfoBuilder.new(repo_path).build(old, new, refname)
      end
    end

    infos.each do |info|
      next if info.branch.start_with?('notes/')
      puts "#{info.branch}: #{info.revision} (#{info.author})"

      from = make_from(name: info.author, email: "noreply@ruby-lang.org")
      sendmail(to, from, make_mail(to, from, info, viewer_uri: options.viewer_uri))
    end
  end

  def sendmail(to, from, mail)
    IO.popen([*SENDMAIL.shellsplit, to], 'w') do |f|
      f.print(mail)
    end
    unless $?.success?
      raise "Failed to run `#{SENDMAIL} #{to}` with: '#{mail}'"
    end
  end

  private

  def b_encode(str)
    NKF.nkf('-WwM', str)
  end

  def make_body(info, viewer_uri:)
    body = +''
    body << "#{info.author}\t#{format_time(info.date)}\n"
    body << "\n"
    body << "  New Revision: #{info.revision}\n"
    body << "\n"
    body << "  #{viewer_uri}#{info.revision}\n"
    body << "\n"
    body << "  Log:\n"
    body << info.log.lstrip.gsub(/^\t*/, '    ').rstrip
    body << "\n\n"
    body << added_dirs(info)
    body << added_files(info)
    body << deleted_dirs(info)
    body << deleted_files(info)
    body << modified_dirs(info)
    body << modified_files(info)
    [body.rstrip].pack('M')
  end

  def format_time(time)
    time.strftime('%Y-%m-%d %X %z (%a, %d %b %Y)')
  end

  def changed_items(title, type, items)
    rv = ''
    unless items.empty?
      rv << "  #{title} #{type}:\n"
      rv << items.collect {|item| "    #{item}\n"}.join('')
    end
    rv
  end

  def changed_files(title, files)
    changed_items(title, 'files', files)
  end

  def added_files(info)
    changed_files('Added', info.added_files)
  end

  def deleted_files(info)
    changed_files('Removed', info.deleted_files)
  end

  def modified_files(info)
    changed_files('Modified', info.updated_files)
  end

  def changed_dirs(title, files)
    changed_items(title, 'directories', files)
  end

  def added_dirs(info)
    changed_dirs('Added', info.added_dirs)
  end

  def deleted_dirs(info)
    changed_dirs('Removed', info.deleted_dirs)
  end

  def modified_dirs(info)
    changed_dirs('Modified', info.updated_dirs)
  end

  def changed_dirs_info(info, uri)
    (info.added_dirs.collect do |dir|
       "  Added: #{dir}\n"
     end + info.deleted_dirs.collect do |dir|
       "  Deleted: #{dir}\n"
     end + info.updated_dirs.collect do |dir|
       "  Modified: #{dir}\n"
     end).join("\n")
  end

  def diff_info(info, uri)
    info.diffs.collect do |key, values|
      [
        key,
        values.collect do |type, value|
          case type
          when :added
            rev = "?revision=#{info.revision}&view=markup"
          when :modified, :property_changed
            prev_revision = (info.revision.is_a?(Integer) ? info.revision - 1 : "#{info.revision}^")
            rev = "?r1=#{info.revision}&r2=#{prev_revision}&diff_format=u"
          when :deleted, :copied
            rev = ''
          else
            raise "unknown diff type: #{value[:type]}"
          end

          link = [uri, key.sub(/ .+/, '') || ''].join('/') + rev

          desc = ''

          [desc, link]
        end
      ]
    end
  end

  def make_header(to, from, info)
    <<~EOS
      Mime-Version: 1.0
      Content-Type: text/plain; charset=utf-8
      Content-Transfer-Encoding: quoted-printable
      From: #{from}
      To: #{to}
      Subject: #{make_subject(info)}
    EOS
  end

  def make_subject(info)
    subject = +''
    subject << "#{info.revision}"
    subject << " (#{info.branch})"
    subject << ': '
    subject << info.log.lstrip.lines.first.to_s.strip
    b_encode(subject)
  end

  # https://tools.ietf.org/html/rfc822#section-4.1
  # https://tools.ietf.org/html/rfc822#section-6.1
  # https://tools.ietf.org/html/rfc822#appendix-D
  # https://tools.ietf.org/html/rfc2047
  def make_from(name:, email:)
    if name.ascii_only?
      escaped_name = name.gsub(/["\\\n]/) { |c| "\\#{c}" }
      %Q["#{escaped_name}" <#{email}>]
    else
      escaped_name = "=?UTF-8?B?#{NKF.nkf('-WwMB', name)}?="
      %Q[#{escaped_name} <#{email}>]
    end
  end

  def make_mail(to, from, info, viewer_uri:)
    make_header(to, from, info) + make_body(info, viewer_uri: viewer_uri)
  end
end

repo_path, to, *rest = ARGV
begin
  CommitEmail.main(repo_path, to, rest)
rescue StandardError => e
  $stderr.puts "#{e.class}: #{e.message}"
  $stderr.puts e.backtrace

  _, options = CommitEmail.parse(rest)
  to = options.error_to
  CommitEmail.sendmail(to, to, <<-MAIL)
From: #{to}
To: #{to}
Subject: Error

#{$!.class}: #{$!.message}
#{$@.join("\n")}
MAIL
  exit 1
end
