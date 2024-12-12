# Reporting Issues
## Reporting security issues

If you've found a security vulnerability, please follow
[these instructions](https://www.ruby-lang.org/en/security/).

## Reporting bugs

If you've encountered a bug in Ruby, please report it to the Redmine issue
tracker available at [bugs.ruby-lang.org](https://bugs.ruby-lang.org/), by
following these steps:

* Check if anyone has already reported your issue by
  searching [the Redmine issue tracker](https://bugs.ruby-lang.org/projects/ruby-master/issues).
* If you haven't already,
  [sign up for an account](https://bugs.ruby-lang.org/account/register) on the
  Redmine issue tracker.
* If you can't find a ticket addressing your issue, please [create a new issue](https://bugs.ruby-lang.org/projects/ruby-master/issues/new). You will need to fill in the subject, description and Ruby version.

    * Ensure the issue exists on Ruby master by trying to replicate your bug on
      the head of master (see ["making changes to Ruby"](making_changes_to_ruby.md)).
    * Write a concise subject and briefly describe your problem in the description section. If
      your issue affects [a released version of Ruby](#label-Backport+requests), please say so.
    * Fill in the Ruby version you're using when experiencing this issue
      (the output of running `ruby -v`).
    * Attach any logs or reproducible programs to provide additional information.
      Any scripts should be as small as possible.
* If the ticket doesn't have any replies after 10 days, you can send a
  reminder.
* Please reply to feedback requests. If a bug report doesn't get any feedback,
  it'll eventually get rejected.

### Reporting website issues

If you're having an issue with the bug tracker or the mailing list, you can
contact the webmaster, Hiroshi SHIBATA (hsbt@ruby-lang.org).

You can report issues with ruby-lang.org on the
[repo's issue tracker](https://github.com/ruby/www.ruby-lang.org/issues).

## Requesting features

If there's a new feature that you want to see added to Ruby, you will need to
write a proposal on [the Redmine issue tracker](https://bugs.ruby-lang.org/projects/ruby-master/issues/new).
When you open the issue, select `Feature` in the Tracker dropdown.

When writing a proposal, be sure to check for previous discussions on the
topic and have a solid use case. You should also consider the potential
compatibility issues that this new feature might raise. Consider making
your feature into a gem, and if there are enough people who benefit from
your feature it could help persuade Ruby core.

Here is a template you can use for a feature proposal:

```markdown
# Abstract

Briefly summarize your feature

# Background

Describe current behavior

# Proposal

Describe your feature in detail

# Use cases

Give specific example uses of your feature

# Discussion

Describe why this feature is necessary and better than using existing features

# See also

Link to other related resources (such as implementations in other languages)
```

## Backport requests

If a bug exists in a released version of Ruby, please report this in the issue.
Once this bug is fixed, the fix can be backported if deemed necessary. Only Ruby
committers can request backporting, and backporting is done by the backport manager.
New patch versions are released at the discretion of the backport manager.

[Ruby versions](https://www.ruby-lang.org/en/downloads/) can be in one of three maintenance states:

* Stable releases: backport any bug fixes
* Security maintenance: only backport security fixes
* End of life: no backports, please upgrade your Ruby version

## Add context to existing issues

There are several ways you can help with a bug that aren't directly
resolving it. These include:

* Verifying or reproducing the existing issue and reporting it
* Adding more specific reproduction instructions
* Contributing a failing test as a patch (see ["making changes to Ruby"](making_changes_to_ruby.md))
* Testing patches that others have submitted (see ["making changes to Ruby"](making_changes_to_ruby.md))
