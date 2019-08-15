# -*- sh -*-

quote() {
    printf "#${indent}define $1"
    shift
    ${1+printf} ${1+' "%s"'$sep} ${1+"$@"}
    echo
}

archs=""
arch_flag=""

parse_arch_flags() {
    for arch in $1; do
	archs="${archs:+$archs }${arch%=*}"
    done

    while shift && [ "$#" -gt 0 ]; do
	case "$1" in
	    -arch)
		shift
		archs="${archs:+$archs }$1"
		;;
	    *)
		arch_flag="${arch_flag:+${arch_flag} }$1"
		;;
	esac
    done
}

define_arch_flags() {
    ${archs:+echo} ${archs:+'#if 0'}
    for arch in $archs; do
	echo "#elif defined __${arch}__"
	quote "MJIT_ARCHFLAG   " -arch "${arch}"
    done
    ${archs:+echo} ${archs:+'#else'}
    quote "MJIT_ARCHFLAG    /* ${arch_flag:-no flag} */" ${arch_flag}
    ${archs:+echo} ${archs:+'#endif'}
}
