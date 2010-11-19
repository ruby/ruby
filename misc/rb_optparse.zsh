#!/bin/zsh
# Completion for zsh:
# (based on <http://d.hatena.ne.jp/rubikitch/20071002/zshcomplete>)
#
# (1) install this file,
#
# (2) load the script, and
#      . ~/.zsh.d/rb_optparse.zsh
#
# (3) geneate completion files once.
#      generate-complete-function/ruby/optparse COMMAND1
#      generate-complete-function/ruby/optparse COMMAND2
#

generate-complete-function/ruby/optparse ()
{
    local cmpl="_${1:t}"
    mkdir -p "${ZSH_COMPLETION_DIR-$HOME/.zsh.d/Completion}"
    $1 --help=zshcomplete="${1:t}" > "${ZSH_COMPLETION_DIR-$HOME/.zsh.d/Completion}/$comp"
    if [[ $(type -w "$cmpl") == "${cmpl}: function" ]]; then
	unfunction "$cmpl"
	autoload -U "$cmpl}"
    else
        compinit "$cmpl"
    fi
}

for cmd in "$@"; do
    generate-complete-function/ruby/optparse "$cmd"
done
