"""Pure signing-input validation. Never logs or exports credentials."""
import base64
import binascii

_ASCII_WHITESPACE = str.maketrans('', '', ' \t\r\n\f\v')


def decode_certificate(encoded: str) -> bytes:
    """Accept conventional line-wrapped Base64, not arbitrary discarded bytes."""
    if not isinstance(encoded, str):
        raise ValueError('MACOS_CERTIFICATE_P12 must be a Base64 string')
    compact = encoded.translate(_ASCII_WHITESPACE)
    if not compact:
        raise ValueError('MACOS_CERTIFICATE_P12 must not be empty')
    try:
        return base64.b64decode(compact, validate=True)
    except (binascii.Error, ValueError):
        raise ValueError('MACOS_CERTIFICATE_P12 must contain valid standard Base64') from None
