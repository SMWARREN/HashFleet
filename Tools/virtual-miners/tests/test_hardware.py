import unittest

from virtual_miners.cosim import GammaBoard, RegisterDevice, _bm_crc5


class HardwareTests(unittest.TestCase):
    def test_gamma_sensor_register_pointer_and_temperature(self):
        board = GammaBoard(temperature_c=50)
        self.assertEqual(board.transfer(0x4C, b"\x01", 1), (True, b"\x32"))
        self.assertEqual(board.transfer(0x4C, b"\x10", 1), (True, b"\x00"))
        self.assertEqual(board.emc2101.registers[0xFD], 0x16)
        self.assertEqual(board.transfer(0x4C, b"\x46", 2), (True, b"\x08\x07"))

    def test_gamma_oled_acks_and_unknown_address_nacks(self):
        board = GammaBoard()
        self.assertEqual(board.transfer(0x3C, b"\x00\xae", 0), (True, b""))
        self.assertEqual(board.transfer(0x22, b"", 1), (False, b""))

    def test_tps546_returns_original_driver_device_id_block(self):
        board = GammaBoard()
        self.assertEqual(board.transfer(0x24, b"\xad", 7),
                         (True, bytes([6, 0x54, 0x49, 0x54, 0x6d, 0x24, 0x41])))
        self.assertEqual(board.transfer(0x24, b"\x79", 2), (True, b"\x00\x00"))
        self.assertEqual(board.transfer(0x24, b"\x88", 2), (True, b"\x05\x00"))
        self.assertEqual(board.transfer(0x24, b"\x8b", 2), (True, b"\x4d\x02"))
        self.assertEqual(board.transfer(0x24, b"\x8c", 2), (True, b"\x0c\x00"))

    def test_scenarios_change_only_their_intended_virtual_hardware(self):
        missing = GammaBoard(scenario="asic-missing")
        self.assertEqual(missing.uart(bytes.fromhex("55 aa 52 05 00 00 0a")), b"")
        overheated = GammaBoard(scenario="overheat")
        self.assertEqual(overheated.emc2101.registers[0x01], 0x5F)
        no_power = GammaBoard(scenario="no-power")
        self.assertEqual(no_power.transfer(0x24, b"\xad", 7), (False, b""))
        self.assertEqual(no_power.transfer(0x4C, b"\x46", 2), (True, b"\x08\x07"))

    def test_register_device_write_and_read_cursor(self):
        dev = RegisterDevice()
        self.assertEqual(dev.transfer(b"\x10\xaa\xbb", 0), (True, b""))
        self.assertEqual(dev.transfer(b"\x10", 2), (True, b"\xaa\xbb"))

    def test_bm1370_chip_id_and_baud_milestones(self):
        board = GammaBoard()
        self.assertEqual(board.uart_baud_milestones, [115200])
        response = board.uart(bytes.fromhex("55 aa 52 05 00 00 0a"))
        self.assertEqual(response, bytes.fromhex("aa 55 13 70 00 00 00 00 00 00 10"))
        self.assertEqual(_bm_crc5(response[2:]), 0)
        board.uart(bytes.fromhex("55 aa 51 09 00 28 11 30 02 00 03"))
        self.assertEqual(board.uart_baud_milestones, [115200, 1_000_000])


if __name__ == "__main__":
    unittest.main()
