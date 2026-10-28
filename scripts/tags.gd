extends RefCounted
## Reads a track's title, artist and cover art from its tags: ID3v2 (MP3,
## or a WAV's id3 chunk), ID3v1 (MP3), Vorbis comments (Ogg) or RIFF INFO
## (WAV).
## Covers are shrunk to SIZE pixels so they show at twice the game
## resolution.

const SIZE := 36
const FRONT_COVER := 3


## {title, artist, cover}: the tagged title and artist, "" where missing,
## and the cover as a Texture2D or null. A <track>.png next to a bundled
## track wins over the embedded art.
static func read(path: String, stream: AudioStream) -> Dictionary:
	var tags := {"title": "", "artist": "", "cover": null}
	# Bundled tracks are imported, so only MP3s keep their original bytes.
	var d := PackedByteArray()
	if stream is AudioStreamMP3:
		d = stream.data
	elif not path.begins_with("res://"):
		d = FileAccess.get_file_as_bytes(path)
	var img: Image
	var magic := d.slice(0, 4).get_string_from_ascii()
	if magic.begins_with("ID3"):
		img = _read_id3(d, tags)
	elif magic == "OggS":
		img = _read_vorbis(d, tags)
	elif magic == "RIFF":
		img = _read_riff(d, tags)
	# The old ID3v1 tag fills in what a newer one left out.
	if d.size() >= 128 and d.slice(-128, -125).get_string_from_ascii() == "TAG":
		_fill(tags, "title", _latin1(_until_zero(d.slice(-125, -95))))
		_fill(tags, "artist", _latin1(_until_zero(d.slice(-95, -65))))
	var override := path.get_basename() + ".png"
	if path.begins_with("res://") and ResourceLoader.exists(override):
		img = load(override).get_image()
	tags.cover = make_cover(img)
	return tags


## img shrunk to a cover, or null if there is no image.
static func make_cover(img: Image) -> Texture2D:
	if not img or img.is_empty():
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	if img.get_size() != Vector2i(SIZE, SIZE):
		# Trilinear averages through mipmaps, so detail blends instead of aliasing.
		img.resize(SIZE, SIZE, Image.INTERPOLATE_TRILINEAR)
	return ImageTexture.create_from_image(img)


## A JPEG, PNG or WebP image from its file bytes, or null.
static func image_from_buffer(data: PackedByteArray) -> Image:
	if data.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if data[0] == 0xFF and data[1] == 0xD8:
		err = img.load_jpg_from_buffer(data)
	elif data.slice(1, 4).get_string_from_ascii() == "PNG":
		err = img.load_png_from_buffer(data)
	elif data.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(data)
	return img if err == OK else null


## Fills tags from an ID3v2.2-2.4 tag and returns its front cover, else
## its first picture.
static func _read_id3(d: PackedByteArray, tags: Dictionary) -> Image:
	if d.size() < 10:
		return null
	var version := d[3]
	var flags := d[5]
	var end := mini(10 + _syncsafe(d, 6), d.size())
	# Unsynchronisation puts a 0 after every 0xFF. Before v2.4 it covers the
	# whole tag, frame headers included; from v2.4 each frame on its own.
	var unsync := flags & 0x80 != 0
	if unsync and version < 4:
		d = d.slice(0, 10) + _resync(d.slice(10, end))
		end = d.size()
	var pos := 10
	if flags & 0x40 and version >= 3:
		pos += _syncsafe(d, pos) if version == 4 else _int32(d, pos) + 4
	var id_len := 3 if version == 2 else 4
	var head_len := 6 if version == 2 else 10
	var first: Image
	while pos + head_len <= end:
		var id := d.slice(pos, pos + id_len).get_string_from_ascii()
		if id.is_empty() or d[pos] == 0:
			break
		var size: int
		if version == 2:
			size = (d[pos + 3] << 16) | (d[pos + 4] << 8) | d[pos + 5]
		elif version == 4:
			size = _syncsafe(d, pos + 4)
		else:
			size = _int32(d, pos + 4)
		var format := d[pos + 9] if version == 4 else 0
		var body := pos + head_len
		pos = body + size
		if pos > end:
			break
		if id not in ["TIT2", "TT2", "TPE1", "TP1", "APIC", "PIC"]:
			continue
		var f := d.slice(body, pos)
		# A v2.4 frame may start with its length before unsynchronisation.
		if format & 0x01:
			f = f.slice(4)
		if version == 4 and (unsync or format & 0x02):
			f = _resync(f)
		match id:
			"TIT2", "TT2":
				_fill(tags, "title", _id3_text(f))
			"TPE1", "TP1":
				_fill(tags, "artist", _id3_text(f))
			"APIC", "PIC":
				var pic := _id3_picture(f, id == "PIC")
				if pic[1] == null:
					continue
				if pic[0] == FRONT_COVER:
					return pic[1]
				if not first:
					first = pic[1]
	return first


## The text of an ID3 text frame; the first value if it holds several.
static func _id3_text(f: PackedByteArray) -> String:
	if f.is_empty():
		return ""
	var body := f.slice(1)
	match f[0]:
		1:
			return _utf16(body, false)
		2:
			return _utf16(body, true)
		3:
			return _until_zero(body).get_string_from_utf8()
		_:
			return _latin1(_until_zero(body))


## [picture type, Image or null] from an APIC (or v2.2 PIC) frame body.
static func _id3_picture(f: PackedByteArray, v22: bool) -> Array:
	if f.size() < 4:
		return [0, null]
	var encoding := f[0]
	var i := 1
	if v22:
		# Three letter image format instead of a MIME type.
		i += 3
	else:
		while i < f.size() and f[i] != 0:
			i += 1
		i += 1
	if i >= f.size():
		return [0, null]
	var type := f[i]
	i += 1
	# Description ends in one zero byte, or two aligned ones for UTF-16.
	if encoding == 1 or encoding == 2:
		while i + 1 < f.size() and not (f[i] == 0 and f[i + 1] == 0):
			i += 2
		i += 2
	else:
		while i < f.size() and f[i] != 0:
			i += 1
		i += 1
	if i >= f.size():
		return [type, null]
	return [type, image_from_buffer(f.slice(i))]


## Fills tags from the Vorbis comment header (the second packet) and
## returns its front cover, else its first picture.
static func _read_vorbis(d: PackedByteArray, tags: Dictionary) -> Image:
	var p := _ogg_packet(d, 1)
	if p.size() < 15 or p[0] != 3 or p.slice(1, 7).get_string_from_ascii() != "vorbis":
		return null
	var i := 7
	i += 4 + p.decode_u32(i)
	if i + 4 > p.size():
		return null
	var count := p.decode_u32(i)
	i += 4
	var first: Image
	for n in count:
		if i + 4 > p.size():
			break
		var length := p.decode_u32(i)
		var entry := p.slice(i + 4, i + 4 + length).get_string_from_utf8()
		i += 4 + length
		var key := entry.get_slice("=", 0).to_upper()
		var value := entry.substr(key.length() + 1)
		match key:
			"TITLE":
				_fill(tags, "title", value)
			"ARTIST":
				_fill(tags, "artist", value)
			"METADATA_BLOCK_PICTURE":
				var pic := _flac_picture(Marshalls.base64_to_raw(value))
				if pic[1] == null:
					continue
				if pic[0] == FRONT_COVER:
					return pic[1]
				if not first:
					first = pic[1]
	return first


## The index-th packet of an Ogg stream, joined from its page segments.
static func _ogg_packet(d: PackedByteArray, index: int) -> PackedByteArray:
	var packet := PackedByteArray()
	var n := 0
	var pos := 0
	while pos + 27 <= d.size() and d.slice(pos, pos + 4).get_string_from_ascii() == "OggS":
		var segments := d[pos + 26]
		var body := pos + 27 + segments
		for s in segments:
			var length := d[pos + 27 + s]
			if n == index:
				packet.append_array(d.slice(body, body + length))
			body += length
			# A segment shorter than 255 bytes ends its packet.
			if length < 255:
				if n == index:
					return packet
				n += 1
		pos = body
	return packet


## [picture type, Image or null] from a FLAC picture block.
static func _flac_picture(b: PackedByteArray) -> Array:
	if b.size() < 32:
		return [0, null]
	var type := _int32(b, 0)
	var i := 4
	i += 4 + _int32(b, i)
	i += 4 + _int32(b, i)
	# Width, height, depth and colour count.
	i += 16
	if i + 4 > b.size():
		return [type, null]
	var length := _int32(b, i)
	return [type, image_from_buffer(b.slice(i + 4, i + 4 + length))]


## Fills tags from a WAV's INFO list or embedded ID3 tag and returns the
## ID3 tag's cover, if any.
static func _read_riff(d: PackedByteArray, tags: Dictionary) -> Image:
	var img: Image
	var pos := 12
	while pos + 8 <= d.size():
		var id := d.slice(pos, pos + 4).get_string_from_ascii()
		var size := d.decode_u32(pos + 4)
		var body := pos + 8
		# Chunks are padded to an even length.
		pos = body + size + (size & 1)
		if id.to_lower() == "id3 ":
			img = _read_id3(d.slice(body, body + size), tags)
		elif id == "LIST" and d.slice(body, body + 4).get_string_from_ascii() == "INFO":
			var i := body + 4
			while i + 8 <= mini(body + size, d.size()):
				var sub := d.slice(i, i + 4).get_string_from_ascii()
				var length := d.decode_u32(i + 4)
				var text := _until_zero(d.slice(i + 8, i + 8 + length)).get_string_from_utf8()
				if sub == "INAM":
					_fill(tags, "title", text)
				elif sub == "IART":
					_fill(tags, "artist", text)
				i += 8 + length + (length & 1)
	return img


## Sets tags[key] to value unless an earlier tag already set it.
static func _fill(tags: Dictionary, key: String, value: String) -> void:
	value = value.strip_edges()
	if tags[key] == "" and value != "":
		tags[key] = value


## UTF-16 text up to its terminator. A byte order mark overrides big_endian.
static func _utf16(b: PackedByteArray, big_endian: bool) -> String:
	if b.size() >= 2 and b[0] == 0xFF and b[1] == 0xFE:
		b = b.slice(2)
		big_endian = false
	elif b.size() >= 2 and b[0] == 0xFE and b[1] == 0xFF:
		b = b.slice(2)
		big_endian = true
	var end := 0
	while end + 1 < b.size() and not (b[end] == 0 and b[end + 1] == 0):
		end += 2
	b = b.slice(0, end)
	if big_endian:
		for i in range(0, b.size() - 1, 2):
			var hi := b[i]
			b[i] = b[i + 1]
			b[i + 1] = hi
	return b.get_string_from_utf16()


## b with unsynchronisation undone: the 0 after each 0xFF dropped.
static func _resync(b: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	var from := 0
	var i := b.find(0xFF)
	while i >= 0 and i + 1 < b.size():
		if b[i + 1] == 0:
			out.append_array(b.slice(from, i + 1))
			from = i + 2
		i = b.find(0xFF, i + 1)
	out.append_array(b.slice(from))
	return out


static func _latin1(b: PackedByteArray) -> String:
	var s := ""
	for c in b:
		s += String.chr(c)
	return s


static func _until_zero(b: PackedByteArray) -> PackedByteArray:
	var end := b.find(0)
	return b if end < 0 else b.slice(0, end)


static func _syncsafe(d: PackedByteArray, i: int) -> int:
	return (d[i] << 21) | (d[i + 1] << 14) | (d[i + 2] << 7) | d[i + 3]


static func _int32(d: PackedByteArray, i: int) -> int:
	return (d[i] << 24) | (d[i + 1] << 16) | (d[i + 2] << 8) | d[i + 3]
