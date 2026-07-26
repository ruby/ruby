#!/bin/bash
set -e

nop=
dump_ast=

opt= optarg=
while getopts cd:n-: opt; do
    optarg="$OPTARG"
    if [[ "$opt" = - ]]; then
        opt="-${optarg%%=*}"
        if [[ "$optarg" = *=* ]]; then optarg="${optarg#*=}";
        elif optarg="${!OPTIND}"; [[ "${optarg}" = -* ]]; then optarg=
        else shift; fi
    fi

    case "-$opt" in
        -c|--clean) nop=:;;
        -n|--dry-run) nop=echo;;
        -d|--dump[-_]ast) dump_ast="$optarg" RUBY_DUMP_AST=;;
        --) break;;
        -*) echo "${0##*/}: Unknown option $1" 1>&2; exit 1;;
    esac
done
shift $((OPTIND-1))

if tooldir="${0%/*}"; [ "$tooldir" = "$0" ]; then
    tooldir=. srcdir=..
elif srcdir="${tooldir%/*}"; [ "$srcdir" = "$tooldir" ]; then
    srcdir=.
fi
template="${srcdir}/template"

[ "$nop" = echo ] || trap 'rm -fr "${clean[@]}"' 0 2

for t in config.status .rbconfig.time Makefile GNUmakefile; do
    [ -z "${nop}" -a -e "$t" ] && echo "exist: $t" && exit 1
done

${nop} touch config.status .rbconfig.time
clean=(config.status .rbconfig.time)
for mk in Makefile GNUmakefile; do
    [ ${nop} ] || sed -f "$tooldir/prereq.status" "$template/$mk.in" > $mk
    clean+=("$mk")
done
clean+=(prism/.time prism/util/.time build-tool)
${nop} make "HAVE_BASERUBY=yes" "BASERUBY=${RUBY-ruby}" \
       ${RUBY_DUMP_AST:+"DUMP_AST=$RUBY_DUMP_AST" "DUMP_AST_TARGET=no"} \
       "${@-prereq}"
[ -z "$dump_ast" ] || ${nop} cp build-tool/dump_ast "$dump_ast"
${nop} rm -fr "${clean[@]}"
