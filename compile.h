#ifndef COMPILE_H
#define COMPILE_H

typedef uint32_t ibf_offset_t;

struct ibf_header {
    char magic[4]; /* YARB */
    uint32_t major_version;
    uint32_t minor_version;
    uint32_t size;
    uint32_t extra_size;

    uint32_t iseq_list_size;
    uint32_t global_object_list_size;
    ibf_offset_t iseq_list_offset;
    ibf_offset_t global_object_list_offset;
    uint8_t endian;
    uint8_t wordsize;           /* assume no 2048-bit CPU */
};

#endif /* COMPILE_H */
