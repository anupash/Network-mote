// see http://www.zlib.net/manual.html for more info

#include <stdio.h>
#include <string.h>
#include <assert.h>
#include "../shared/structs.h"
#include "zlib.h"

/* see if the dimension is important or not */
#define CHUNK 100
#define LEVEL Z_BEST_COMPRESSION

// TODO: see how much data has the last one
// compress original data in the given result
int payload_compress(payload_t data, payload_t result) {
    int ret;
    z_stream strm;
    // maybe out should be bigger
    unsigned char *in = (unsigned char *) data.stream;
    unsigned char *out = (unsigned char *) result.stream;

    /* allocate deflate state */
    // initialize the structures
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    strm.opaque = Z_NULL;
    ret = deflateInit(&strm, LEVEL);
    // if initialized correctly
    if (ret != Z_OK)
        return ret;

    strm.avail_in = data.len;
    strm.avail_out = data.len;
    
    // is this thing enough for it?
    strm.next_in = in;
    strm.next_out = out;
    ret = deflate(&strm, Z_NO_FLUSH);    /* no bad return value */
    printf("now ret in and out = %d, %d, %d\n", ret, strm.avail_in, strm.avail_out);
    // the initialization was successful
    assert(ret != Z_STREAM_ERROR);  /* state not clobbered */

    return Z_OK;
}

int payload_decompress(payload_t data, payload_t result) {
    z_stream strm;
    int ret;
    // maybe out should be bigger
    unsigned char *in = (unsigned char *) data.stream;
    unsigned char *out = (unsigned char *) result.stream;
    
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    strm.opaque = Z_NULL;
    ret = deflateInit(&strm, LEVEL);
    ret = inflateInit(&strm);
    
    if (ret != Z_OK)
        return ret;

    strm.avail_in = data.len;
    strm.avail_out = data.len;
    strm.next_in = in;
    strm.next_out = out;
    ret = inflate(&strm, Z_NO_FLUSH);    /* no bad return value */
    printf("now ret in and out = %d, %d, %d\n", ret, strm.avail_in, strm.avail_out);
    // the initialization was successful
    assert(ret != Z_STREAM_ERROR);  /* state not clobbered */
    
    inflateEnd(&strm);
    return Z_OK;
}

    /* /\* compress until end of file *\/ */
    /* do { */
    /*     strm.avail_in = fread(in, 1, CHUNK, source); */
    /*     if (ferror(source)) { */
    /*         (void)deflateEnd(&strm); */
    /*         return Z_ERRNO; */
    /*     } */
    /*     flush = feof(source) ? Z_FINISH : Z_NO_FLUSH; */
    /*     strm.next_in = in; */

    /*     /\* run deflate() on input until output buffer not full, finish */
    /*        compression if all of source has been read in *\/ */
    /*     do { */
    /*         strm.avail_out = CHUNK; */
    /*         strm.next_out = out; */
    /*         ret = deflate(&strm, flush);    /\* no bad return value *\/ */
    /*         assert(ret != Z_STREAM_ERROR);  /\* state not clobbered *\/ */
    /*         have = CHUNK - strm.avail_out; */
    /*         // when there is nothing else to add */
    /*         if (fwrite(out, 1, have, dest) != have || ferror(dest)) { */
    /*             (void)deflateEnd(&strm); */
    /*             return Z_ERRNO; */
    /*         } */
    /*     } while (strm.avail_out == 0); */
    /*     assert(strm.avail_in == 0);     /\* all input will be used *\/ */

    /*     /\* done when last data in file processed *\/ */
    /* } while (flush != Z_FINISH); */
    /* assert(ret == Z_STREAM_END);        /\* stream will be complete *\/ */

    /* /\* clean up and return *\/ */
    /* (void)deflateEnd(&strm); */


/* Decompress from file source to file dest until stream ends or EOF.
   inf() returns Z_OK on success, Z_MEM_ERROR if memory could not be
   allocated for processing, Z_DATA_ERROR if the deflate data is
   invalid or incomplete, Z_VERSION_ERROR if the version of zlib.h and
   the version of the library linked do not match, or Z_ERRNO if there
   is an error reading or writing the files. */
int inf(FILE *source, FILE *dest)
{
    int ret;
    unsigned have;
    z_stream strm;
    unsigned char in[CHUNK];
    unsigned char out[CHUNK];

    /* allocate inflate state */
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    strm.opaque = Z_NULL;
    strm.avail_in = 0;
    strm.next_in = Z_NULL;
    ret = inflateInit(&strm);
    if (ret != Z_OK)
        return ret;

    /* decompress until deflate stream ends or end of file */
    do {
        strm.avail_in = fread(in, 1, CHUNK, source);
        if (ferror(source)) {
            (void)inflateEnd(&strm);
            return Z_ERRNO;
        }
        if (strm.avail_in == 0)
            break;
        strm.next_in = in;

        /* run inflate() on input until output buffer not full */
        do {
            strm.avail_out = CHUNK;
            strm.next_out = out;
            ret = inflate(&strm, Z_NO_FLUSH);
            assert(ret != Z_STREAM_ERROR);  /* state not clobbered */
            switch (ret) {
            case Z_NEED_DICT:
                ret = Z_DATA_ERROR;     /* and fall through */
            case Z_DATA_ERROR:
            case Z_MEM_ERROR:
                (void)inflateEnd(&strm);
                return ret;
            }
            have = CHUNK - strm.avail_out;
            if (fwrite(out, 1, have, dest) != have || ferror(dest)) {
                (void)inflateEnd(&strm);
                return Z_ERRNO;
            }
        } while (strm.avail_out == 0);

        /* done when inflate() says it's done */
    } while (ret != Z_STREAM_END);

    /* clean up and return */
    (void)inflateEnd(&strm);
    return ret == Z_STREAM_END ? Z_OK : Z_DATA_ERROR;
}

// not really needed maybe, use perror instead
/* report a zlib or i/o error */
void zerr(int ret) {
    fputs("zpipe: ", stderr);
    switch (ret) {
    case Z_ERRNO:
        if (ferror(stdin))
            fputs("error reading stdin\n", stderr);
        if (ferror(stdout))
            fputs("error writing stdout\n", stderr);
        break;
    case Z_STREAM_ERROR:
        fputs("invalid compression level\n", stderr);
        break;
    case Z_DATA_ERROR:
        fputs("invalid or incomplete deflate data\n", stderr);
        break;
    case Z_MEM_ERROR:
        fputs("out of memory\n", stderr);
        break;
    case Z_VERSION_ERROR:
        fputs("zlib version mismatch!\n", stderr);
    }
}

/* compress or decompress from stdin to stdout */
/* int main(int argc, char **argv) { */
/*     int ret; */

/*     /\* avoid end-of-line conversions *\/ */
/*     /\* SET_BINARY_MODE(stdin); *\/ */
/*     /\* SET_BINARY_MODE(stdout); *\/ */

/*     /\* do compression if no arguments *\/ */
/*     if (argc == 1) { */
/*         ret = def(stdin, stdout, Z_DEFAULT_COMPRESSION); */
/*         if (ret != Z_OK) */
/*             zerr(ret); */
/*         return ret; */
/*     } */

/*     /\* do decompression if -d specified *\/ */
/*     else if (argc == 2 && strcmp(argv[1], "-d") == 0) { */
/*         ret = inf(stdin, stdout); */
/*         if (ret != Z_OK) */
/*             zerr(ret); */
/*         return ret; */
/*     } */

/*     /\* otherwise, report usage *\/ */
/*     else { */
/*         fputs("zpipe usage: zpipe [-d] < source > dest\n", stderr); */
/*         return 1; */
/*     } */
/* } */