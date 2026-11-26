"""Virtual Gamma 601 board peripherals used by the co-simulation sidecar.

The register behavior is intentionally small and evidence-scoped: it covers
EMC2101 temperature reads, the ESP-Miner TPS546 block-ID probe, and an OLED
I2C ACK. It is not a complete regulator/fan/display electrical model.
"""

from .cosim import GammaBoard, RegisterDevice, Tps546Device

__all__ = ["GammaBoard", "RegisterDevice", "Tps546Device"]
