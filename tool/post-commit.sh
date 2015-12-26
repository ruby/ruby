#!/bin/sh

{ date; echo '### start ###'; uptime; } >> /tmp/post-commit.log

PATH=/opt/csw/bin:/usr/sfw/bin:/usr/bin:/bin
export PATH
HOME=/home/svn
export HOME

REPOS="$1"
REV="$2"

{ date; echo $REPOS; echo $REV; echo svnadmin; uptime; } >> /tmp/post-commit.log

svnadmin dump -q -r "$REV" --incremental "$REPOS" | bzip2 -c > /var/svn/dump/ruby/$REV.bz2

{ date; echo commit-email.rb; uptime; } >> /tmp/post-commit.log

~svn/scripts/svn-utils/bin/commit-email.rb \
   "$REPOS" "$REV" ruby-cvs@ruby-lang.org \
   -I ~svn/scripts/svn-utils/lib \
   --name Ruby \
   --viewvc-uri http://svn.ruby-lang.org/cgi-bin/viewvc.cgi \
   -r http://svn.ruby-lang.org/repos/ruby \
   --rss-path /tmp/ruby.rdf \
   --rss-uri http://svn.ruby-lang.org/rss/ruby.rdf \
   --error-to cvs-admin@ruby-lang.org

{ date; echo update-version.h.rb; uptime; } >> /tmp/post-commit.log

~svn/scripts/svn-utils/bin/update-version.h.rb "$REPOS" "$REV" &

#~svn/scripts/svn-utils/bin/commit-email-test.rb \
#   "$REPOS" "$REV" eban@ruby-lang.org \
#   -I ~svn/scripts/svn-utils/lib \
#   --name Ruby \
#   --viewvc-uri http://svn.ruby-lang.org/cgi-bin/viewvc.cgi \
#   --error-to eban@ruby-lang.org

#   --from admin@ruby-lang.org
#   -r http://svn.ruby-lang.org/repos/ruby \
#   --rss-path ~/ruby.rdf \
#   --rss-uri http://svn.ruby-lang.org/rss/ruby.rdf \

{ date; echo redmine fetch changesets; uptime; } >> /tmp/post-commit.log

curl "https://bugs.ruby-lang.org/sys/fetch_changesets?key=`cat ~svn/config/redmine.key`" &

{ date; echo auto-style; uptime; } >> /tmp/post-commit.log

~svn/scripts/svn-utils/bin/auto-style.rb ~svn/ruby/trunk &

{ date; echo github sync; uptime; } >> /tmp/post-commit.log

cd /var/git-svn/ruby
sudo -u git git svn fetch --all

# Push branch or tag
for ref in `svnlook changed -r $REV $REPOS | grep '^[AU ]' |                                            sed 's!^..  \(\(trunk\)/.*\|\(tags\|branches\)/\([^/]*\)/.*\)!\2\4!' | sort -u`; do
  case $ref in
  trunk) sudo -u git git push origin svn/trunk:trunk ;;
  ruby_*) sudo -u git git push origin svn/$ref:$ref ;;
  v*) echo git tag -f $ref svn/tags/$ref && git push origin $ref ;;
  esac
done

# Delete tags or branches
for ref in `svnlook changed -r $REV $REPOS |                                                            grep '^D   \(tags\|branches\)/[^/]*/$' | sed 's!^D   \(tags\|branches\)/\([^/]*\)/$!\2!'`; do
  sudo -u git git push origin :$ref
done

{ date; echo '### end ###'; uptime; } >> /tmp/post-commit.log
