#ifndef OBJSPACE_H
#define OBJSPACE_H 1

/* objspace.c */
size_t memsize_of(VALUE obj);

/* object_tracing.c */
struct allocation_info {
    const char *path;
    unsigned long line;
    const char *class_path;
    VALUE mid;
    size_t generation;
};
struct allocation_info *lookup_allocation_info(VALUE obj);

#endif
