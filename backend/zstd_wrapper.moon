-- ZSTD-FFI Wrapper
-- Optimized ZSTD compression/decompression with proper memory management

ffi = require('ffi')

-- ZSTD FFI definitions with additional functions for better decompression
ffi.cdef[[
    typedef struct ZSTD_CCtx_s ZSTD_CCtx;
    typedef struct ZSTD_DCtx_s ZSTD_DCtx;

    size_t ZSTD_compress(void* dst, size_t dstCapacity, const void* src, size_t srcSize, int compressionLevel);
    size_t ZSTD_decompress(void* dst, size_t dstCapacity, const void* src, size_t compressedSize);
    unsigned long long ZSTD_getFrameContentSize(const void* src, size_t srcSize);
    unsigned ZSTD_isError(size_t code);
    const char* ZSTD_getErrorName(size_t code);
    int ZSTD_maxCLevel(void);
    size_t ZSTD_compressBound(size_t srcSize);
]]

zstd = ffi.load('zstd')

-- Constants for error handling (ZSTD_CONTENTSIZE_ERROR = (1ULL<<63))
ZSTD_CONTENTSIZE_ERROR = tonumber('9223372036854775808')

ZstdWrapper = {}

-- Compress data using ZSTD-FFI with optimized memory usage
ZstdWrapper.compress_zstd = (data, options = {}) ->
  level = options.level or 1

  -- Validate input
  unless type(data) == 'string'
    return nil, "Input must be a string"

  unless type(level) == 'number' and level >= 1 and level <= zstd.ZSTD_maxCLevel()
    return nil, "Compression level must be between 1 and #{zstd.ZSTD_maxCLevel()}"

  -- Get max compressed size
  src_size = #data
  max_compressed_size = zstd.ZSTD_compressBound(src_size)

  -- Allocate buffer for compressed data
  compressed_buf = ffi.new('char[?]', max_compressed_size)

  -- Compress
  compressed_size = zstd.ZSTD_compress(compressed_buf, max_compressed_size, data, src_size, level)

  if zstd.ZSTD_isError(compressed_size) ~= 0
    error_msg = ffi.string(zstd.ZSTD_getErrorName(compressed_size))
    return nil, "Compression failed: #{error_msg}"

  -- Convert to Lua string
  result = ffi.string(compressed_buf, compressed_size)
  return result

-- Decompress ZSTD compressed data with proper size detection
ZstdWrapper.decompress_zstd = (compressed_data) ->
  -- Validate input
  unless type(compressed_data) == 'string'
    return nil, "Input must be a string"

  -- Get exact decompressed size from frame header
  content_size = zstd.ZSTD_getFrameContentSize(compressed_data, #compressed_data)

  -- Handle errors in size detection
  if content_size == ZSTD_CONTENTSIZE_ERROR
    return nil, "Invalid ZSTD frame"

  -- If size is unknown, use fallback with reasonable limit
  if content_size == 0
    -- Fallback: estimate based on compression ratio (max 20x)
    max_decompressed_size = math.min(#compressed_data * 20, 50 * 1024 * 1024) -- 50MB max
  else
    max_decompressed_size = content_size

  -- Allocate buffer for decompressed data
  decompressed_buf = ffi.new('char[?]', max_decompressed_size)

  -- Decompress
  decompressed_size = zstd.ZSTD_decompress(decompressed_buf, max_decompressed_size, compressed_data, #compressed_data)

  if zstd.ZSTD_isError(decompressed_size) ~= 0
    error_msg = ffi.string(zstd.ZSTD_getErrorName(decompressed_size))
    return nil, "Decompression failed: #{error_msg}"

  -- Convert to Lua string
  result = ffi.string(decompressed_buf, decompressed_size)
  return result

-- Check if data is ZSTD compressed by checking magic number
-- ZSTD magic number: 0x28, 0xb5, 0x2f, 0xfd
ZstdWrapper.is_zstd_compressed = (data) ->
  unless type(data) == 'string' and #data >= 4
    return false

  -- Check ZSTD magic number: 0x28 0xb5 0x2f 0xfd
  magic = data\sub(1, 4)
  zstd_magic = string.char(0x28, 0xb5, 0x2f, 0xfd)

  return magic == zstd_magic

-- Get compression info about compressed data
ZstdWrapper.get_compression_info = (compressed_data) ->
  unless ZstdWrapper.is_zstd_compressed(compressed_data)
    return nil, "Data is not ZSTD compressed"

  -- Try to get original size
  content_size = zstd.ZSTD_getFrameContentSize(compressed_data, #compressed_data)
  original_size = if content_size > 0 then content_size else 'unknown'

  return {
    format: 'ZSTD'
    compressed_size: #compressed_data
    original_size: original_size
    is_compressed: true
  }

-- Test function with validation
ZstdWrapper.test = ->
  test_data = "Hello World - ZSTD compression test"
  compressed, err = ZstdWrapper.compress_zstd(test_data, {level: 1})
  if err
    return "Compression error: #{err}"

  decompressed, err2 = ZstdWrapper.decompress_zstd(compressed)
  if err2
    return "Decompression error: #{err2}"

  is_zstd = ZstdWrapper.is_zstd_compressed(compressed)
  info = ZstdWrapper.get_compression_info(compressed)

  return {
    original: test_data
    compressed_size: #compressed
    decompressed: decompressed
    is_zstd: is_zstd
    success: decompressed == test_data
    info: info
  }

ZstdWrapper
