"""Native/website destination parity, without logging public receiving addresses."""
import hmac
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CryptoSupportParityTests(unittest.TestCase):
    def test_native_destinations_exactly_match_website(self):
        website = (ROOT / "website/src/lib/support.ts").read_text()
        native = (ROOT / "Sources/HashFleetCore/DeveloperSupportCrypto.swift").read_text()
        web_destinations = re.findall(r"symbol: '([^']+)'.*?address: '([^']+)'", website)
        native_destinations = re.findall(r'case \.(bitcoin|ethereum|solana): "([^"\n]+)"', native)
        # The enum contains display names and addresses. Select only the address switch.
        native_addresses = dict(native_destinations)
        names = {"BTC": "bitcoin", "ETH": "ethereum", "SOL": "solana"}
        self.assertEqual([symbol for symbol, _ in web_destinations], list(names))
        for symbol, address in web_destinations:
            self.assertTrue(hmac.compare_digest(native_addresses.get(names[symbol], ""), address),
                            f"{symbol} native/website mismatch")

    def test_no_transaction_links_or_dynamic_destinations(self):
        native = (ROOT / "Sources/HashFleetCore/DeveloperSupportCrypto.swift").read_text()
        for forbidden in ["bitcoin:", "ethereum:", "solana:", "URL(string:", "UserDefaults", "URLSession"]:
            # Case labels are enum cases, not URI string literals.
            self.assertNotIn('"' + forbidden, native)


if __name__ == "__main__":
    unittest.main()
