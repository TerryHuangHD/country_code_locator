import 'dart:typed_data';

const List<int> _nibbleTable = <int>[
  0x00000000,
  0x1db71064,
  0x3b6e20c8,
  0x26d930ac,
  0x76dc4190,
  0x6b6b51f4,
  0x4db26158,
  0x5005713c,
  0xedb88320,
  0xf00f9344,
  0xd6d6a3e8,
  0xcb61b38c,
  0x9b64c2b0,
  0x86d3d2d4,
  0xa00ae278,
  0xbdbdf21c,
];

int crc32(Uint8List bytes, int start, int end) {
  var crc = 0xffffffff;
  for (var index = start; index < end; index += 1) {
    crc ^= bytes[index];
    crc = (crc >> 4) ^ _nibbleTable[crc & 0x0f];
    crc = (crc >> 4) ^ _nibbleTable[crc & 0x0f];
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
