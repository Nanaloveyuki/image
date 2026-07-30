///|
fn sample_image() -> Image {
  try! Image::new(
    2, 2, b"\xff\x00\x00\xff\x00\xff\x00\x80\x00\x00\xff\x40\xff\xff\xff\x00",
  )
}

///|
fn test_write_u32_be(output : Buffer, value : Int) -> Unit {
  output.write_byte(((value >> 24) & 0xff).to_byte())
  output.write_byte(((value >> 16) & 0xff).to_byte())
  output.write_byte(((value >> 8) & 0xff).to_byte())
  output.write_byte((value & 0xff).to_byte())
}

///|
fn test_write_png_chunk(output : Buffer, kind : Bytes, payload : Bytes) -> Unit {
  test_write_u32_be(output, payload.length())
  output.write_bytes(kind[:])
  output.write_bytes(payload[:])
  let crc = @checksum.Crc32::new()
  crc.update(kind[:])
  crc.update(payload[:])
  test_write_u32_be(output, crc.finish().reinterpret_as_int())
}

///|
fn png_with_trns(
  color_type : Int,
  transparency : Bytes,
  scanline : Bytes,
) -> Bytes {
  let header = Buffer()
  test_write_u32_be(header, 1)
  test_write_u32_be(header, 1)
  header.write_byte(b'\x08')
  header.write_byte(color_type.to_byte())
  header.write_bytes(b"\x00\x00\x00")
  let output = Buffer()
  output.write_bytes(b"\x89PNG\r\n\x1a\n")
  test_write_png_chunk(output, b"IHDR", header.to_bytes())
  test_write_png_chunk(output, b"tRNS", transparency)
  test_write_png_chunk(output, b"IDAT", @zlib.zlib_compress(scanline))
  test_write_png_chunk(output, b"IEND", b"")
  output.to_bytes()
}

///|
test "PNG roundtrip preserves RGBA8" {
  let image = sample_image()
  let decoded = try! decode_png(try! encode_png(image, compression_level=6))
  inspect(decoded == image, content="true")
}

///|
test "PNG encoding is deterministic for a fixed level" {
  let image = sample_image()
  let first = try! encode_png(image, compression_level=6)
  let second = try! encode_png(image, compression_level=6)
  inspect(first == second, content="true")
}

///|
test "PNG grayscale tRNS color key becomes transparent alpha" {
  let png = png_with_trns(0, b"\x00\x80", b"\x00\x80")
  let image = try! decode_png(png)
  inspect(image.pixels, content="b\"\\x80\\x80\\x80\\x00\"")
}

///|
test "PNG RGB tRNS color key becomes transparent alpha" {
  let png = png_with_trns(2, b"\x00\x11\x00\x22\x00\x33", b"\x00\x11\x22\x33")
  let image = try! decode_png(png)
  inspect(image.pixels[0], content="b'\\x11'")
  inspect(image.pixels[1], content="b'\\x22'")
  inspect(image.pixels[2], content="b'\\x33'")
  inspect(image.pixels[3], content="b'\\x00'")
}

///|
test "PNG rejects invalid tRNS length" {
  let png = png_with_trns(2, b"\x00", b"\x00\x11\x22\x33")
  let rejected = try decode_png(png) catch {
    ImageError(InvalidInput, _) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(rejected, content="true")
}

///|
test "Lanczos resize avoids transparent color fringes" {
  let image = try! Image::new(2, 1, b"\xff\xff\xff\xff\xff\x00\x00\x00")
  let resized = try! resize_lanczos3(image, 1, 1)
  inspect(resized.pixels[0], content="b'\\xFF'")
  inspect(resized.pixels[1], content="b'\\xFF'")
  inspect(resized.pixels[2], content="b'\\xFF'")
}

///|
test "strict square policy rejects a rectangle" {
  let image = try! Image::new(2, 1, b"\x00\x00\x00\xff\x00\x00\x00\xff")
  let rejected = try square_image(image) catch {
    ImageError(NotSquare, _) => true
    _ => false
  } noraise {
    _ => false
  }
  inspect(rejected, content="true")
}

///|
test "ICO uses PNG image entries" {
  let ico = try! encode_ico(sample_image(), sizes=[16, 32])
  inspect(ico[0:4] == b"\x00\x00\x01\x00"[:], content="true")
  inspect(ico[4:6] == b"\x02\x00"[:], content="true")
  inspect(ico[6], content="b'\\x10'")
}

///|
test "ICNS contains standard and retina PNG chunks" {
  let icns = try! encode_icns(sample_image(), sizes=[16, 32])
  inspect(icns[:4] == b"icns"[:], content="true")
  let has_icp5 = icns[8:12] == b"icp4"[:] || icns[8:12] == b"icp5"[:]
  inspect(has_icp5, content="true")
  inspect(icns.length() > 16, content="true")
}
