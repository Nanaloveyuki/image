///|
let png_signature = b"\x89PNG\r\n\x1a\n"

///|
fn validate_chunk_crc(
  kind : BytesView,
  payload : BytesView,
  expected : Int,
) -> Bool {
  let crc = @checksum.Crc32::new()
  crc.update(kind[:])
  crc.update(payload[:])
  crc.finish().reinterpret_as_int() == expected
}

///|
fn inflate_png_idat(input : Bytes, limit : Int) -> Bytes raise ImageError {
  let decoder = @zlib.Decoder::new()
  let output = Buffer()
  let scratch = FixedArray::make(32768, b'\x00')
  let mut position = 0
  while !decoder.is_finished() {
    let _ = decoder.step(input[position:], scratch.mut_view(), end=true) catch {
      _ => raise ImageError(InvalidInput, "PNG IDAT zlib stream is invalid")
    }
    let consumed = decoder.last_consumed()
    let produced = decoder.last_produced()
    if output.length() > limit - produced {
      raise ImageError(
        ResourceLimit,
        "PNG decompressed data exceeds image bounds",
      )
    }
    for i in 0..<produced {
      output.write_byte(scratch[i])
    }
    position = position + consumed
    if consumed == 0 && produced == 0 && !decoder.is_finished() {
      raise ImageError(InvalidInput, "PNG IDAT zlib stream made no progress")
    }
  }
  if !decoder.unused_input().is_empty() {
    raise ImageError(InvalidInput, "PNG IDAT contains trailing zlib data")
  }
  output.to_bytes()
}

///|
/// Decode a non-interlaced, 8-bit PNG into RGBA8. Every chunk checksum and the
/// zlib Adler-32 checksum are verified before returning pixels.
pub fn decode_png(
  input : Bytes,
  limits? : DecodeLimits = default_decode_limits(),
) -> Image raise ImageError {
  if input.length() > limits.max_input_bytes {
    raise ImageError(ResourceLimit, "PNG input exceeds max_input_bytes")
  }
  if input.length() < 8 || input[:8] != png_signature[:] {
    raise ImageError(InvalidInput, "not a PNG signature")
  }
  let mut offset = 8
  let mut width = 0
  let mut height = 0
  let mut color_type = -1
  let mut channels = 0
  let mut got_ihdr = false
  let mut got_iend = false
  let mut palette : Bytes? = None
  let mut transparency : Bytes? = None
  let idat = Buffer()
  while offset < input.length() {
    if input.length() - offset < 12 {
      raise ImageError(InvalidInput, "truncated PNG chunk")
    }
    let length = u32_be(input, offset)
    if length < 0 || length > input.length() - offset - 12 {
      raise ImageError(InvalidInput, "invalid PNG chunk length")
    }
    let kind = input[offset + 4:offset + 8]
    let payload = input[offset + 8:offset + 8 + length]
    let expected_crc = u32_be(input, offset + 8 + length)
    if !validate_chunk_crc(kind, payload, expected_crc) {
      raise ImageError(InvalidInput, "PNG chunk checksum mismatch")
    }
    offset = offset + 12 + length
    if kind == b"IHDR"[:] {
      if got_ihdr || length != 13 {
        raise ImageError(InvalidInput, "invalid PNG IHDR")
      }
      width = u32_be(payload, 0)
      height = u32_be(payload, 4)
      if width <= 0 ||
        height <= 0 ||
        width > limits.max_dimension ||
        height > limits.max_dimension ||
        width > limits.max_pixels / height {
        raise ImageError(ResourceLimit, "PNG dimensions exceed decode limits")
      }
      if payload[8].to_int() != 8 ||
        payload[10].to_int() != 0 ||
        payload[11].to_int() != 0 ||
        payload[12].to_int() != 0 {
        raise ImageError(
          UnsupportedFormat,
          "only non-interlaced 8-bit PNG is supported",
        )
      }
      color_type = payload[9].to_int()
      channels = match color_type {
        0 => 1
        2 => 3
        3 => 1
        4 => 2
        6 => 4
        _ => raise ImageError(UnsupportedFormat, "unsupported PNG color type")
      }
      got_ihdr = true
    } else if kind == b"PLTE"[:] {
      if !got_ihdr || length == 0 || length % 3 != 0 || length > 768 {
        raise ImageError(InvalidInput, "invalid PNG palette")
      }
      palette = Some(Bytes::from_array(payload.to_array()))
    } else if kind == b"tRNS"[:] {
      transparency = Some(Bytes::from_array(payload.to_array()))
    } else if kind == b"IDAT"[:] {
      if !got_ihdr || got_iend {
        raise ImageError(InvalidInput, "PNG IDAT is out of order")
      }
      idat.write_bytes(payload)
    } else if kind == b"IEND"[:] {
      if length != 0 || !got_ihdr {
        raise ImageError(InvalidInput, "invalid PNG IEND")
      }
      got_iend = true
      if offset != input.length() {
        raise ImageError(InvalidInput, "trailing data after PNG IEND")
      }
    }
  }
  if !got_ihdr || !got_iend || idat.length() == 0 {
    raise ImageError(InvalidInput, "PNG is missing required chunks")
  }
  if color_type == 3 && palette is None {
    raise ImageError(InvalidInput, "indexed PNG is missing PLTE")
  }
  let row_bytes = width * channels
  let expected = height * (row_bytes + 1)
  let inflated = inflate_png_idat(idat.to_bytes(), expected)
  if inflated.length() != expected {
    raise ImageError(InvalidInput, "PNG scanline data length is invalid")
  }
  let scanlines = Array::make(height * row_bytes, b'\x00')
  let rgba = Array::make(width * height * 4, b'\x00')
  for y in 0..<height {
    let source = y * (row_bytes + 1)
    let filter = inflated[source].to_int()
    if filter < 0 || filter > 4 {
      raise ImageError(InvalidInput, "invalid PNG scanline filter")
    }
    for x in 0..<row_bytes {
      let raw = inflated[source + 1 + x].to_int()
      let left = if x >= channels {
        scanlines[y * row_bytes + x - channels].to_int()
      } else {
        0
      }
      let above = if y > 0 {
        scanlines[(y - 1) * row_bytes + x].to_int()
      } else {
        0
      }
      let upper_left = if y > 0 && x >= channels {
        scanlines[(y - 1) * row_bytes + x - channels].to_int()
      } else {
        0
      }
      let value = match filter {
        0 => raw
        1 => (raw + left) & 0xff
        2 => (raw + above) & 0xff
        3 => (raw + ((left + above) >> 1)) & 0xff
        _ => (raw + paeth(left, above, upper_left)) & 0xff
      }
      scanlines[y * row_bytes + x] = value.to_byte()
    }
    for x in 0..<width {
      let src = y * row_bytes + x * channels
      let dst = (y * width + x) * 4
      match color_type {
        0 => {
          let g = scanlines[src]
          rgba[dst] = g
          rgba[dst + 1] = g
          rgba[dst + 2] = g
          rgba[dst + 3] = b'\xff'
        }
        2 => {
          rgba[dst] = scanlines[src]
          rgba[dst + 1] = scanlines[src + 1]
          rgba[dst + 2] = scanlines[src + 2]
          rgba[dst + 3] = b'\xff'
        }
        3 => {
          let index = scanlines[src].to_int()
          let p = match palette {
            Some(value) => value
            None => raise ImageError(InvalidInput, "missing PNG palette")
          }
          if index * 3 + 2 >= p.length() {
            raise ImageError(InvalidInput, "PNG palette index is out of range")
          }
          rgba[dst] = p[index * 3]
          rgba[dst + 1] = p[index * 3 + 1]
          rgba[dst + 2] = p[index * 3 + 2]
          rgba[dst + 3] = match transparency {
            Some(alpha) =>
              if index < alpha.length() {
                alpha[index]
              } else {
                b'\xff'
              }
            None => b'\xff'
          }
        }
        4 => {
          let g = scanlines[src]
          rgba[dst] = g
          rgba[dst + 1] = g
          rgba[dst + 2] = g
          rgba[dst + 3] = scanlines[src + 1]
        }
        _ => {
          rgba[dst] = scanlines[src]
          rgba[dst + 1] = scanlines[src + 1]
          rgba[dst + 2] = scanlines[src + 2]
          rgba[dst + 3] = scanlines[src + 3]
        }
      }
    }
  }
  Image::new(width, height, Bytes::from_array(rgba))
}

///|
fn write_png_chunk(out : Buffer, kind : Bytes, payload : Bytes) -> Unit {
  write_u32_be(out, payload.length())
  out.write_bytes(kind[:])
  out.write_bytes(payload[:])
  let crc = @checksum.Crc32::new()
  crc.update(kind[:])
  crc.update(payload[:])
  write_u32_be(out, crc.finish().reinterpret_as_int())
}

///|
/// Encode image pixels as a deterministic RGBA PNG with no metadata chunks.
pub fn encode_png(
  image : Image,
  compression_level? : Int = 6,
) -> Bytes raise ImageError {
  let expected = image.width * image.height
  if image.width <= 0 ||
    image.height <= 0 ||
    expected > 0x3fffffff / 4 ||
    image.pixels.length() != expected * 4 {
    raise ImageError(InvalidDimensions, "invalid RGBA8 image")
  }
  let raw = Buffer()
  for y in 0..<image.height {
    raw.write_byte(b'\x00')
    let start = y * image.width * 4
    raw.write_bytes(image.pixels[start:start + image.width * 4])
  }
  let header = Buffer()
  write_u32_be(header, image.width)
  write_u32_be(header, image.height)
  header.write_bytes(b"\x08\x06\x00\x00\x00")
  let output = Buffer()
  output.write_bytes(png_signature[:])
  write_png_chunk(output, b"IHDR", header.to_bytes())
  write_png_chunk(
    output,
    b"IDAT",
    @zlib.zlib_compress(raw.to_bytes(), level=compression_level),
  )
  write_png_chunk(output, b"IEND", b"")
  output.to_bytes()
}
