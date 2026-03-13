local ffi = require('ffi')
ffi.cdef([[    typedef struct ZSTD_CCtx_s ZSTD_CCtx;
    typedef struct ZSTD_DCtx_s ZSTD_DCtx;

    size_t ZSTD_compress(void* dst, size_t dstCapacity, const void* src, size_t srcSize, int compressionLevel);
    size_t ZSTD_decompress(void* dst, size_t dstCapacity, const void* src, size_t compressedSize);
    unsigned long long ZSTD_getFrameContentSize(const void* src, size_t srcSize);
    unsigned ZSTD_isError(size_t code);
    const char* ZSTD_getErrorName(size_t code);
    int ZSTD_maxCLevel(void);
    size_t ZSTD_compressBound(size_t srcSize);
]])
local zstd = ffi.load('zstd')
local ZSTD_CONTENTSIZE_ERROR = tonumber('9223372036854775808')
local ZstdWrapper = { }
ZstdWrapper.compress_zstd = function(data, options)
  if options == nil then
    options = { }
  end
  local level = options.level or 1
  if not (type(data) == 'string') then
    return nil, "Input must be a string"
  end
  if not (type(level) == 'number' and level >= 1 and level <= zstd.ZSTD_maxCLevel()) then
    return nil, "Compression level must be between 1 and " .. tostring(zstd.ZSTD_maxCLevel())
  end
  local src_size = #data
  local max_compressed_size = zstd.ZSTD_compressBound(src_size)
  local compressed_buf = ffi.new('char[?]', max_compressed_size)
  local compressed_size = zstd.ZSTD_compress(compressed_buf, max_compressed_size, data, src_size, level)
  if zstd.ZSTD_isError(compressed_size) ~= 0 then
    local error_msg = ffi.string(zstd.ZSTD_getErrorName(compressed_size))
    return nil, "Compression failed: " .. tostring(error_msg)
  end
  local result = ffi.string(compressed_buf, compressed_size)
  return result
end
ZstdWrapper.decompress_zstd = function(compressed_data)
  if not (type(compressed_data) == 'string') then
    return nil, "Input must be a string"
  end
  local content_size = zstd.ZSTD_getFrameContentSize(compressed_data, #compressed_data)
  if content_size == ZSTD_CONTENTSIZE_ERROR then
    return nil, "Invalid ZSTD frame"
  end
  if content_size == 0 then
    local max_decompressed_size = math.min(#compressed_data * 20, 50 * 1024 * 1024)
  else
    local max_decompressed_size = content_size
  end
  local decompressed_buf = ffi.new('char[?]', max_decompressed_size)
  local decompressed_size = zstd.ZSTD_decompress(decompressed_buf, max_decompressed_size, compressed_data, #compressed_data)
  if zstd.ZSTD_isError(decompressed_size) ~= 0 then
    local error_msg = ffi.string(zstd.ZSTD_getErrorName(decompressed_size))
    return nil, "Decompression failed: " .. tostring(error_msg)
  end
  local result = ffi.string(decompressed_buf, decompressed_size)
  return result
end
ZstdWrapper.is_zstd_compressed = function(data)
  if not (type(data) == 'string' and #data >= 4) then
    return false
  end
  local magic = data:sub(1, 4)
  local zstd_magic = string.char(0x28, 0xb5, 0x2f, 0xfd)
  return magic == zstd_magic
end
ZstdWrapper.get_compression_info = function(compressed_data)
  if not (ZstdWrapper.is_zstd_compressed(compressed_data)) then
    return nil, "Data is not ZSTD compressed"
  end
  local content_size = zstd.ZSTD_getFrameContentSize(compressed_data, #compressed_data)
  local original_size
  if content_size > 0 then
    original_size = content_size
  else
    original_size = 'unknown'
  end
  return {
    format = 'ZSTD',
    compressed_size = #compressed_data,
    original_size = original_size,
    is_compressed = true
  }
end
ZstdWrapper.test = function()
  local test_data = "Hello World - ZSTD compression test"
  local compressed, err = ZstdWrapper.compress_zstd(test_data, {
    level = 1
  })
  if err then
    return "Compression error: " .. tostring(err)
  end
  local decompressed, err2 = ZstdWrapper.decompress_zstd(compressed)
  if err2 then
    return "Decompression error: " .. tostring(err2)
  end
  local is_zstd = ZstdWrapper.is_zstd_compressed(compressed)
  local info = ZstdWrapper.get_compression_info(compressed)
  return {
    original = test_data,
    compressed_size = #compressed,
    decompressed = decompressed,
    is_zstd = is_zstd,
    success = decompressed == test_data,
    info = info
  }
end
return ZstdWrapper
