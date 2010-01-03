#ifdef BITSIZE_OF_VALUE
#define DO_DEFINE_VALUE(sz) typedef uint ## sz ## _t VALUE
#define DEFINE_VALUE(sz) DO_DEFINE_VALUE(sz)
DEFINE_VALUE(BITSIZE_OF_VALUE);
#else
# error BITSIZE_OF_VALUE is not defined.
#endif
provider ruby {
    probe method__entry(VALUE receiver, char *classname, char *methodname, char *sourcefile, int sourceline);
    probe method__return(VALUE receiver, char *classname, char *methodname, char *sourcefile, int sourceline);
    probe raise(VALUE exception, char *classname, char *sourcefile, int sourceline);
    probe rescue(VALUE exception, char *classname, char *sourcefile, int sourceline);
    probe line(char* sourcefile, int sourceline);

    /* gc probes */
    probe gc__begin();
    probe gc__end();

    /* threads and fibers */
    probe thread__init(VALUE thread, char *sourcefile, int sourceline);
    probe thread__term(VALUE thread, char *sourcefile, int sourceline);
    probe thread__enter(VALUE thread, char *sourcefile, int sourceline);
    probe thread__leave(VALUE thread, char *sourcefile, int sourceline);

    /* Some initial memory type probes */
    probe object__create(VALUE obj, char *classname, char *sourcefile, int sourceline);
    probe object__free(VALUE obj);

    /* VM proves */
    probe insn__entry(char *insnname, VALUE *operands, char *sourcefile, int sourceline);
    probe insn__return(char *insnname, VALUE *operands, char *sourcefile, int sourceline);

    probe ruby__probe(char *name, char *data);
};

#pragma D attributes Evolving/Evolving/Common provider ruby provider 
#pragma D attributes Private/Private/Unknown provider ruby module 
#pragma D attributes Private/Private/Unknown provider ruby function 
#pragma D attributes Evolving/Evolving/Unknown provider ruby name 
#pragma D attributes Evolving/Evolving/Unknown provider ruby args 

