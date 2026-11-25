import socket
import struct
import threading
import unittest
from virtual_miners.cosim import (GammaBoard, _bm_crc5, _bytes_field, _decode, _vfield,
                                  attach, attach_uart1)


def read_message(sock):
    def exact(n):
        data = bytearray()
        while len(data) < n:
            data.extend(sock.recv(n - len(data)))
        return bytes(data)
    size = struct.unpack("<I", exact(4))[0]
    return exact(size)


class CosimTests(unittest.TestCase):
    def test_attach_claims_board_and_returns_original_driver_i2c_read(self):
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0)); listener.listen()
        port = listener.getsockname()[1]
        stop = threading.Event()
        board = GammaBoard(50)
        worker = threading.Thread(target=attach, args=(port, board, stop), kwargs={"scl": 48, "sda": 47})
        worker.start()
        peer, _ = listener.accept()
        peer.settimeout(2)
        try:
            length = struct.unpack("<I", peer.recv(4))[0]
            registration = bytearray()
            while len(registration) < length: registration.extend(peer.recv(length - len(registration)))
            reg = _decode(_decode(bytes(registration))[4])
            self.assertEqual((reg[1], reg[2]), (1, b"gamma-board"))
            claim = _decode(reg[3])
            i2c_claim = _decode(claim[2])
            self.assertEqual(i2c_claim[1], 0x3C)
            _send_peer(peer, b"@gamma-board", _bytes_field(5, _vfield(5, 1)))
            bus_req = _vfield(1, 9) + _bytes_field(2, _vfield(1, 0) + _vfield(2, 0x24) + _bytes_field(3, b"\xad") + _vfield(4, 7))
            _send_peer(peer, b"", _bytes_field(7, bus_req))
            decoded_response = _decode(read_message(peer))
            reply = _decode(decoded_response[8])
            self.assertEqual((reply[1], reply[2]), (9, 1))
            self.assertEqual(reply[3], bytes([6, 0x54, 0x49, 0x54, 0x6d, 0x24, 0x41]))
            self.assertTrue(board.marker)
        finally:
            stop.set(); peer.close(); listener.close(); worker.join(1)

    def test_uart1_tcp_returns_bm1370_chip_id_fixture(self):
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0)); listener.listen()
        port = listener.getsockname()[1]
        stop = threading.Event()
        events = []
        worker = threading.Thread(target=attach_uart1, args=(port, GammaBoard(), stop),
                                  kwargs={"on_event": events.append})
        worker.start()
        peer, _ = listener.accept()
        peer.settimeout(2)
        try:
            peer.sendall(bytes.fromhex("55 aa 52 05 00 00 0a"))
            response = bytearray()
            while len(response) < 11:
                response.extend(peer.recv(11 - len(response)))
            self.assertEqual(bytes(response), bytes.fromhex("aa 55 13 70 00 00 00 00 00 00 10"))
            self.assertEqual(_bm_crc5(bytes(response[2:])), 0)
            self.assertEqual(events[0]["type"], "bm1370_chip_id_read")
            self.assertLessEqual(len(events[0]["rx_hex"]), 32)
            self.assertLessEqual(len(events[0]["tx_hex"]), 32)
        finally:
            stop.set(); peer.close(); listener.close(); worker.join(1)


def _send_peer(sock, topic, payload):
    frame = struct.pack("<H", len(topic)) + topic + payload
    sock.sendall(struct.pack("<I", len(frame)) + frame)
