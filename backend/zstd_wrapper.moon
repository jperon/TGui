-- ZSTD Compression Wrapper
-- Provides a clean API for luajit-zstd compression

zstd = require('zstd')

-- ZSTD compression wrapper with consistent API
ZstdWrapper = {}

-- Compress data using ZSTD with specified level
-- @param data: string to compress
-- @param options: table with compression options (level default 1)
-- @return: compressed bytes or nil, error message
ZstdWrapper.compress_zstd = (data, options = {}) ->
  level = options.level or 1

  -- Validate input
  unless type(data) == 'string'
    return nil, "Input must be a string"

  unless type(level) == 'number' and level >= 1 and level <= 22
    return nil, "Compression level must be between 1 and 22"

  -- Compress data
  compressed, err = zstd.compress(data, level)

  if err
    return nil, "Compression failed: #{err}"

  return compressed

-- Decompress ZSTD compressed data
-- @param compressed_data: bytes to decompress
-- @return: decompressed string or nil, error message
ZstdWrapper.decompress_zstd = (compressed_data) ->
  -- Validate input
  unless type(compressed_data) == 'string'
    return nil, "Input must be a string"

  -- Decompress data
  decompressed, err = zstd.decompress(compressed_data)

  if err
    return nil, "Decompression failed: #{err}"

  return decompressed

-- Check if data is ZSTD compressed by checking magic number
-- ZSTD magic number: 0x28, 0xb5, 0x2f, 0xfd
-- @param data: bytes to check
-- @return: boolean indicating if data appears to be ZSTD compressed
ZstdWrapper.is_zstd_compressed = (data) ->
  unless type(data) == 'string' and #data >= 4
    return false

  -- Check ZSTD magic number: 0x28 0xb5 0x2f 0xfd
  magic = data\sub(1, 4)
  zstd_magic = string.char(0x28, 0xb5, 0x2f, 0xfd)

  return magic == zstd_magic

-- Get compression info about compressed data
-- @param compressed_data: bytes to analyze
-- @return: table with info or nil, error message
ZstdWrapper.get_compression_info = (compressed_data) ->
  unless ZstdWrapper.is_zstd_compressed(compressed_data)
    return nil, "Data is not ZSTD compressed"

  return {
    format: 'ZSTD'
    compressed_size: #compressed_data
    is_compressed: true
  }

-- Test function for debugging
ZstdWrapper.test = ->
  test_data = "Hello World"
  compressed, err = ZstdWrapper.compress_zstd(test_data, {level: 1})
  if err
    return "Compression error: #{err}"

  decompressed, err2 = ZstdWrapper.decompress_zstd(compressed)
  if err2
    return "Decompression error: #{err2}"

  is_zstd = ZstdWrapper.is_zstd_compressed(compressed)

  return {
    original: test_data
    compressed_size: #compressed
    decompressed: decompressed
    is_zstd: is_zstd
    success: decompressed == test_data
  }

ZstdWrapper
