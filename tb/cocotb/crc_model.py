"""Bit-serial CRC-16 reference (Rocksoft model).

MSB first. ``refin`` reflects each input byte before it is shifted.
``refout`` reflects the remainder before ``xorout``. This is not the RTL;
``run.py`` checks it against the catalogue values in SPEC.md.
"""


def rev8(byte):
    return int(f"{byte & 0xFF:08b}"[::-1], 2)


def rev16(value):
    return int(f"{value & 0xFFFF:016b}"[::-1], 2)


def crc16(data, poly, init, xorout, refin, refout):
    crc = init & 0xFFFF
    poly &= 0xFFFF
    for byte in data:
        bits = rev8(byte) if refin else (byte & 0xFF)
        for index in range(8):
            bit = (bits >> (7 - index)) & 1
            feedback = ((crc >> 15) ^ bit) & 1
            crc = ((crc << 1) & 0xFFFF) ^ (poly if feedback else 0)
    if refout:
        crc = rev16(crc)
    return (crc ^ (xorout & 0xFFFF)) & 0xFFFF


# name, poly, init, xorout, refin, refout, check("123456789")
CATALOGUE = (
    ("CRC-16/CCITT-FALSE", 0x1021, 0xFFFF, 0x0000, False, False, 0x29B1),
    ("CRC-16/ARC", 0x8005, 0x0000, 0x0000, True, True, 0xBB3D),
    ("CRC-16/MODBUS", 0x8005, 0xFFFF, 0x0000, True, True, 0x4B37),
    ("CRC-16/XMODEM", 0x1021, 0x0000, 0x0000, False, False, 0x31C3),
    ("CRC-16/X-25", 0x1021, 0xFFFF, 0xFFFF, True, True, 0x906E),
    ("CRC-16/KERMIT", 0x1021, 0x0000, 0x0000, True, True, 0x2189),
)

CHECK_MESSAGE = b"123456789"


def assert_catalogue():
    for name, poly, init, xorout, refin, refout, expect in CATALOGUE:
        got = crc16(CHECK_MESSAGE, poly, init, xorout, refin, refout)
        if got != expect:
            raise AssertionError(f"{name} model got 0x{got:04X}, catalogue 0x{expect:04X}")
