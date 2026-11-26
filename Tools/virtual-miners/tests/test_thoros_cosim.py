import socket
import struct
import threading
import unittest

from virtual_miners.config import Miner
from virtual_miners.cosim import _bm_crc5, _bytes_field, _decode, _vfield
from virtual_miners.thoros_cosim import (
    THOR_TPS546_ADDR,
    THOR_TPS546_SCL,
    THOR_TPS546_SDA,
    ThorBoard,
    attach_thor_i2c,
    attach_thor_uart1,
    i2c_dev_args,
)


def _read_message(sock: socket.socket) -> bytes:
    def exact(n: int) -> bytes:
        data = bytearray()
        while len(data) < n:
            data.extend(sock.recv(n - len(data)))
        return bytes(data)
    size = struct.unpack("<I", exact(4))[0]
    return exact(size)


def _send_peer(sock: socket.socket, topic: bytes, payload: bytes) -> None:
    frame = struct.pack("<H", len(topic)) + topic + payload
    sock.sendall(struct.pack("<I", len(frame)) + frame)


class ThorOSCosimTests(unittest.TestCase):
    def test_i2c_dev_args_sets_husb_and_tmp75(self):
        miner = Miner("thor-x1", "thor-x1", "esp-emu", 18293, temperature_c=42.0)
        args = i2c_dev_args(miner)
        self.assertIn("0:0x4d,fill=0,reg=0x00=0x2a", args)
        self.assertTrue(any(a.startswith("0:0x42,") for a in args))

        hot = Miner("thor-x1", "thor-x1", "esp-emu", 18293, scenario="overheat", temperature_c=42.0)
        self.assertIn("0:0x4d,fill=0,reg=0x00=0x5f", i2c_dev_args(hot))

    def test_tps546_id_and_operation_telemetry(self):
        board = ThorBoard(temperature_c=52.0, power_w=12.0)
        ack, data = board.transfer(THOR_TPS546_ADDR, b"\xad", 7)
        self.assertTrue(ack)
        self.assertEqual(data, bytes([6]) + bytes.fromhex("54 49 54 6d 24 41"))

        # Off by default: STATUS_WORD has bit 6 (0x0040) set, READ_VOUT is 0
        _, status_off = board.transfer(THOR_TPS546_ADDR, b"\x79", 2)
        self.assertEqual(int.from_bytes(status_off, "little"), 0x0040)
        _, vout_off = board.transfer(THOR_TPS546_ADDR, b"\x8b", 2)
        self.assertEqual(int.from_bytes(vout_off, "little"), 0)

        # Set VOUT_COMMAND to 0.98 V and enable OPERATION
        raw_v = round(0.98 * 512)
        board.transfer(THOR_TPS546_ADDR, bytes([0x21, raw_v & 0xFF, raw_v >> 8]), 0)
        board.transfer(THOR_TPS546_ADDR, bytes([0x01, 0x80]), 0)
        _, status_on = board.transfer(THOR_TPS546_ADDR, b"\x79", 2)
        self.assertEqual(int.from_bytes(status_on, "little"), 0x0000)
        _, vout_on = board.transfer(THOR_TPS546_ADDR, b"\x8b", 2)
        self.assertEqual(int.from_bytes(vout_on, "little"), raw_v)

    def test_no_power_scenario_nacks_tps546(self):
        board = ThorBoard(scenario="no-power")
        ack, data = board.transfer(THOR_TPS546_ADDR, b"\xad", 7)
        self.assertFalse(ack)
        self.assertEqual(data, b"")

    def test_uart_chip_id_and_asic_missing(self):
        chip_read = bytes.fromhex("55 aa 52 05 00 00 0a")
        board = ThorBoard(chip_count=2)
        resp = board.uart(chip_read)
        self.assertEqual(len(resp), 18)  # 2 chips * 9 bytes
        self.assertEqual(resp[:4], bytes.fromhex("aa 55 13 73"))
        self.assertEqual(_bm_crc5(resp[2:9]), 0)
        self.assertEqual(_bm_crc5(resp[11:18]), 0)

        missing = ThorBoard(scenario="asic-missing")
        self.assertEqual(missing.uart(chip_read), b"")

    def test_attach_thor_i2c_claims_gpio_12_11_and_answers_tps546(self):
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        port = listener.getsockname()[1]
        stop = threading.Event()
        board = ThorBoard(temperature_c=45.0)
        worker = threading.Thread(target=attach_thor_i2c, args=(port, board, stop))
        worker.start()
        peer, _ = listener.accept()
        peer.settimeout(2)
        try:
            reg_msg = _decode(_read_message(peer))[4]
            reg = _decode(reg_msg)
            claim = _decode(reg[3])
            i2c_claim = _decode(claim[2])
            self.assertEqual((i2c_claim[1], i2c_claim[2], i2c_claim[3]),
                             (THOR_TPS546_ADDR, THOR_TPS546_SCL, THOR_TPS546_SDA))
            _send_peer(peer, b"@gamma-board", _bytes_field(5, _vfield(5, 1)))
            bus_req = _vfield(1, 3) + _bytes_field(
                2, _vfield(1, 0) + _vfield(2, THOR_TPS546_ADDR) + _bytes_field(3, b"\xad") + _vfield(4, 7)
            )
            _send_peer(peer, b"", _bytes_field(7, bus_req))
            reply = _decode(_decode(_read_message(peer))[8])
            self.assertEqual((reply[1], reply[2]), (3, 1))
            self.assertEqual(reply[3], bytes([6, 0x54, 0x49, 0x54, 0x6D, 0x24, 0x41]))
        finally:
            stop.set()
            peer.close()
            listener.close()
            worker.join(1)

    def test_attach_thor_uart1_answers_bm1373_id(self):
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        port = listener.getsockname()[1]
        stop = threading.Event()
        events: list[dict[str, object]] = []
        worker = threading.Thread(
            target=attach_thor_uart1, args=(port, ThorBoard(), stop),
            kwargs={"on_event": events.append},
        )
        worker.start()
        peer, _ = listener.accept()
        peer.settimeout(2)
        try:
            peer.sendall(bytes.fromhex("55 aa 52 05 00 00 0a"))
            response = bytearray()
            while len(response) < 9:
                response.extend(peer.recv(9 - len(response)))
            self.assertEqual(response[:4], bytes.fromhex("aa 55 13 73"))
            self.assertEqual(_bm_crc5(bytes(response[2:])), 0)
            self.assertEqual(events[0]["type"], "bm1373_chip_id_read")
        finally:
            stop.set()
            peer.close()
            listener.close()
            worker.join(1)


if __name__ == "__main__":
    unittest.main()
