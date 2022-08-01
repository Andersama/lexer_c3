module wheathash;

usize _wheatp0 = 0xa0761d6478bd642f;
usize _wheatp1 = 0xe7037ed1a0b428db;
usize _wheatp2 = 0x8ebc6af09c88c6e3;
usize _wheatp3 = 0x589965cc75374cc3;
usize _wheatp4 = 0x1d8e4e27c47d124f;
usize _wheatp5 = 0xeb44accab455d165;

fn usize _wheatmum(usize a, usize b) {
	usize r = a * b;
	return r - (r >> 32);
}

fn usize _wheatr08(char *p) {
	char v;
	mem::memcpy(&v, p, 1);
	return v;
}

fn usize _wheatr16(char *p) {
	ushort v;
	mem::memcpy(&v, p, 2);
	return v;
}

fn usize _wheatr32(char *p) {
	uint v;
	mem::memcpy(&v, p, 4);
	return v;
}

fn usize wheathash(void *key, uint len, usize seed) {
	char *p = ( char *)key;
	uint       i;
	for (i = 0; i + 16 <= len; i += 16, p += 16) {
		seed = _wheatmum(_wheatmum(_wheatr32(p) ^ _wheatp1, _wheatr32(p + 4) ^ _wheatp2) + seed,
		                 _wheatmum(_wheatr32(p + 8) ^ _wheatp3, _wheatr32(p + 12) ^ _wheatp4));
	}
	seed += _wheatp5;
	switch (len & 15) {
	case 1:
		seed = _wheatmum(_wheatp2 ^ seed, _wheatr08(p) ^ _wheatp1);
		break;
	case 2:
		seed = _wheatmum(_wheatp3 ^ seed, _wheatr16(p) ^ _wheatp4);
		break;
	case 3:
		seed = _wheatmum(_wheatr16(p) ^ seed, _wheatr08(p + 2) ^ _wheatp2);
		break;
	case 4:
		seed = _wheatmum(_wheatr16(p) ^ seed, _wheatr16(p + 2) ^ _wheatp3);
		break;
	case 5:
		seed = _wheatmum(_wheatr32(p) ^ seed, _wheatr08(p + 4) ^ _wheatp1);
		break;
	case 6:
		seed = _wheatmum(_wheatr32(p) ^ seed, _wheatr16(p + 4) ^ _wheatp1);
		break;
	case 7:
		seed = _wheatmum(_wheatr32(p) ^ seed, (_wheatr16(p + 4) << 8 | _wheatr08(p + 6)) ^ _wheatp1);
		break;
	case 8:
		seed = _wheatmum(_wheatr32(p) ^ seed, _wheatr32(p + 4) ^ _wheatp0);
		break;
	case 9:
		seed = _wheatmum(_wheatr32(p) ^ seed, _wheatr32(p + 4) ^ _wheatp2) ^
		       _wheatmum(seed ^ _wheatp4, _wheatr08(p + 8) ^ _wheatp3);
		break;
	case 10:
		seed =
			_wheatmum(_wheatr32(p) ^ seed, _wheatr32(p + 4) ^ _wheatp2) ^ _wheatmum(seed, _wheatr16(p + 8) ^ _wheatp3);
		break;
	case 11:
		seed = _wheatmum(_wheatr32(p) ^ seed, _wheatr32(p + 4) ^ _wheatp2) ^
		       _wheatmum(seed, ((_wheatr16(p + 8) << 8) | _wheatr08(p + 10)) ^ _wheatp3);
		break;
	case 12:
		seed =
			_wheatmum(_wheatr32(p) ^ seed, _wheatr32(p + 4) ^ _wheatp2) ^ _wheatmum(seed ^ _wheatr32(p + 8), _wheatp4);
		break;
	case 13:
		seed = _wheatmum(_wheatr32(p) ^ seed, _wheatr32(p + 4) ^ _wheatp2) ^
		       _wheatmum(seed ^ _wheatr32(p + 8), (_wheatr08(p + 12)) ^ _wheatp4);
		break;
	case 14:
		seed = _wheatmum(_wheatr32(p) ^ seed, _wheatr32(p + 4) ^ _wheatp2) ^
		       _wheatmum(seed ^ _wheatr32(p + 8), (_wheatr16(p + 12)) ^ _wheatp4);
		break;
	case 15:
		seed = _wheatmum(_wheatr32(p) ^ seed, _wheatr32(p + 4) ^ _wheatp2) ^
		       _wheatmum(seed ^ _wheatr32(p + 8), (_wheatr16(p + 12) << 8 | _wheatr08(p + 14)) ^ _wheatp4);
		break;
	}
	seed = (seed ^ seed << 16) * (len ^ _wheatp0);
	return seed - (seed >> 31) + (seed << 33);
}