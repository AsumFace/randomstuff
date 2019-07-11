module zstdc;

extern(C):
nothrow:
@nogc:

size_t ZSTD_compress(
    void* dst, size_t dstCapacity,
    const(void)* src, size_t srcSize,
    int compressionLevel);
size_t ZSTD_decompress(
    void* dst, size_t dstCapacity,
    const(void)* src, size_t compressedSize);

enum ZSTD_CONTENTSIZE_UNKNOWN = size_t.max;
enum ZSTD_CONTENTSIZE_ERROR = size_t.max - 1;
ulong ZSTD_getFrameContentSize(const(void)* src, size_t srcSize);

ulong ZSTD_getDecompressedSize(const(void)* src, size_t srcSize);

size_t ZSTD_findFrameCompressedSize(const(void)* src, size_t srcSize);

size_t ZSTD_compressBound(size_t srcSize)
{
    return ((srcSize) + ((srcSize)>>8) + (((srcSize) < (128<<10)) ? (((128<<10) - (srcSize)) >> 11) : 0));
}

uint ZSTD_isError(size_t code);
const(char)* ZSTD_getErrorName(size_t code);
int ZSTD_minCLevel();
int ZSTD_maxCLevel();

struct ZSTD_CCtx;
ZSTD_CCtx* ZSTD_createCCtx();
size_t ZSTD_freeCCtx(ZSTD_CCtx* cctx);

struct ZSTD_DCtx;
ZSTD_DCtx* ZSTD_createDCtx();
size_t ZSTD_freeDCtx(ZSTD_DCtx* dctx);

size_t ZSTD_decompressDCtx(ZSTD_DCtx* dctx,
    void* dst, size_t dstCapacity,
    const(void)* src, size_t srcSize);


enum ZSTD_strategy
{
    ZSTD_fast = 1,
    ZSTD_dfast = 2,
    ZSTD_greedy = 3,
    ZSTD_lazy = 4,
    ZSTD_lazy2 = 5,
    ZSTD_btlazy2 = 6,
    ZSTD_btopt = 7,
    ZSTD_btultra = 8,
    ZSTD_btultra2 = 9
}

enum ZSTD_cParameter
{
        ZSTD_c_compressionLevel = 100,
        ZSTD_c_windowLog = 101,
        ZSTD_c_hashLog = 102,
        ZSTD_c_chainLog = 103,
        ZSTD_c_searchLog = 104,
        ZSTD_c_minMatch = 105,
        ZSTD_c_targetLength = 106,
        ZSTD_c_strategy = 107,
        ZSTD_c_enableLongDistanceMatching = 160,
        ZSTD_c_ldmHashLog = 161,
        ZSTD_c_ldmMinMatch = 162,
        ZSTD_c_ldmBucketSizeLog = 163,
        ZSTD_c_ldmHashRateLog = 164,
        ZSTD_c_contentSizeFlag = 200,
        ZSTD_c_checksumFlag = 201,
        ZSTD_c_dictIDFlag = 202,
        ZSTD_c_nbWorkers = 400,
        ZSTD_c_jobSize = 401,
        ZSTD_c_overlapLog = 402
}

struct ZSTD_bounds
{
    size_t error;
    int lowerBound;
    int upperBound;
}

ZSTD_bounds ZSTD_cParam_getBounds(ZSTD_cParameter cParam);

size_t ZSTD_CCtx_setParameter(ZSTD_CCtx* cctx, ZSTD_cParameter param, int value);

size_t ZSTD_CCtx_setPledgedSrcSize(ZSTD_CCtx* cctx, ulong pledgedSrcSize);

enum ZSTD_ResetDirective
{
    ZSTD_reset_session_only = 1,
    ZSTD_reset_parameters = 2,
    ZSTD_reset_session_and_parameters = 3
}

size_t ZSTD_CCtx_reset(ZSTD_CCtx* cctx, ZSTD_ResetDirective reset);

size_t ZSTD_compress2(ZSTD_CCtx* cctx,
    void* dst, size_t dstCapacity,
    const(void)* src, size_t srcSize);

enum ZSTD_dParameter
{
    ZSTD_d_windowLogMax = 100
}

ZSTD_bounds ZSTD_dParam_getBounds(ZSTD_dParameter dParam);

size_t ZSTD_DCtx_setParameter(ZSTD_DCtx* dctx, ZSTD_dParameter param, int value);

size_t ZSTD_DCtx_reset(ZSTD_DCtx* dctx, ZSTD_ResetDirective reset);

struct ZSTD_inBuffer
{
    const(void)* src;
    size_t size;
    size_t pos;
}

struct ZSTD_outBuffer
{
    void* dst;
    size_t size;
    size_t pos;
}

alias ZSTD_CStream = ZSTD_CCtx;

ZSTD_CStream* ZSTD_createCStream();
size_t ZSTD_freeCStream(ZSTD_CStream* zcs);

enum ZSTD_EndDirective
{
    ZSTD_e_continue = 0,
    ZSTD_e_flush = 1,
    ZSTD_e_end = 2
}

size_t ZSTD_compressStream2(ZSTD_CCtx* cctx,
    ZSTD_outBuffer* output, ZSTD_inBuffer* input,
    ZSTD_EndDirective endOp);

size_t ZSTD_CStreamInSize();

size_t ZSTD_CStreamOutSize();


alias ZSTD_DStream = ZSTD_DCtx;

ZSTD_DStream* ZSTD_createDStream();
size_t ZSTD_freeDStream(ZSTD_DStream* zds);



size_t ZSTD_initDStream(ZSTD_DStream* zds);
size_t ZSTD_decompressStream(ZSTD_DStream* zds, ZSTD_outBuffer* output, ZSTD_inBuffer* input);


size_t ZSTD_DStreamInSize();

size_t ZSTD_DStreamOutSize();


struct ZSTD_CDict;
struct ZSTD_DDict;

ZSTD_CDict* ZSTD_createCDict(
    const(void)* dictBuffer, size_t dictSize,
    int compressionLevel);

size_t ZSTD_freeCDict(ZSTD_CDict* CDict);

size_t ZSTD_compress_usingCDict(ZSTD_CCtx* cctx,
    void* dst, size_t dstCapacity,
    const(void)* src, size_t srcSize,
    const(ZSTD_CDict)* cdict);

ZSTD_DDict* ZSTD_createDDict(const(void)* dictBuffer, size_t dictSize);

size_t ZSTD_freeDDict(ZSTD_DDict* ddict);

size_t ZSTD_decompress_usingDDict(ZSTD_DCtx* dctx,
    void* dst, size_t dstCapacity,
    const(void)* src, size_t srcSize,
    const(ZSTD_DDict)* ddict);
