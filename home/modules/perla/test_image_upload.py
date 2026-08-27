#!/usr/bin/env python3
"""Tests for the image-attachment feature (/api/text + image data URL).

The web UI sends a user-picked image as a base64 data URL; the daemon decodes
it into a temp file in PERLA_SCREENSHOT_DIR, attaches it to the OpenCode
message, then deletes it so it never lingers on disk.

    Run:  python3 test_image_upload.py
"""
import base64
import importlib.util
import os
import shutil
import sys
import tempfile
import unittest

MODULE_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, MODULE_DIR)


def load_companion():
    spec = importlib.util.spec_from_file_location(
        "perla_companion",
        os.path.join(MODULE_DIR, "perla-companion.py"),
    )
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

TINY_PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489"
    "0000000d4944415478da63fcf9f367030000060001c53d8b120000000049454e44"
    "ae426082"
)


def data_url(content, mime="image/png", bad_b64=False):
    payload = "not-base64!!" if bad_b64 else base64.b64encode(content).decode("ascii")
    return f"data:{mime};base64,{payload}"


class DecodeUploadImageTests(unittest.TestCase):
    """decode_upload_image(data_url) -> (path, error)"""

    @classmethod
    def setUpClass(cls):
        cls.old_dir = os.environ.get("PERLA_SCREENSHOT_DIR")
        cls.shot_dir = tempfile.mkdtemp(prefix="perla-upload-test-")
        os.environ["PERLA_SCREENSHOT_DIR"] = cls.shot_dir
        cls.pc = load_companion()

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.shot_dir, ignore_errors=True)
        if cls.old_dir:
            os.environ["PERLA_SCREENSHOT_DIR"] = cls.old_dir
        else:
            os.environ.pop("PERLA_SCREENSHOT_DIR", None)

    def tearDown(self):
        for name in os.listdir(self.shot_dir):
            os.unlink(os.path.join(self.shot_dir, name))

    def test_valid_png_writes_file_with_correct_bytes(self):
        path, err = self.pc.decode_upload_image(data_url(TINY_PNG), "pic.png")
        self.assertIsNone(err)
        self.assertTrue(path and os.path.isfile(path))
        self.assertTrue(path.startswith(self.shot_dir))
        self.assertTrue(path.endswith(".png"))
        with open(path, "rb") as f:
            self.assertEqual(f.read(), TINY_PNG)

    def test_valid_jpeg_gets_jpg_extension(self):
        path, err = self.pc.decode_upload_image(data_url(os.urandom(64), mime="image/jpeg"), "photo.jpeg")
        self.assertIsNone(err)
        self.assertTrue(path.endswith(".jpg"))

    def test_rejects_oversized_image(self):
        big = os.urandom(10 * 1024 * 1024 + 1)
        path, err = self.pc.decode_upload_image(data_url(big), "big.png")
        self.assertIsNone(path)
        self.assertIn("too large", err)

    def test_size_exactly_at_cap_is_accepted(self):
        cap = self.pc.MAX_IMAGE_UPLOAD_BYTES
        path, err = self.pc.decode_upload_image(data_url(os.urandom(cap)), "exact.png")
        # decoded size == cap: accepted (strictly over is rejected)
        self.assertIsNone(err)
        self.assertTrue(path)

    def test_rejects_non_image_mime(self):
        path, err = self.pc.decode_upload_image(data_url(b"hello", mime="text/plain"), "note.txt")
        self.assertIsNone(path)
        self.assertIn("unsupported", err)

    def test_rejects_unknown_image_mime(self):
        path, err = self.pc.decode_upload_image(data_url(b"x", mime="image/bmp"), "x.bmp")
        self.assertIsNone(path)
        self.assertIn("unsupported", err)

    def test_rejects_not_a_data_url(self):
        path, err = self.pc.decode_upload_image("http://example.com/x.png", "x.png")
        self.assertIsNone(path)
        self.assertIn("data:", err)

    def test_rejects_invalid_base64(self):
        path, err = self.pc.decode_upload_image(data_url(b"", bad_b64=True), "bad.png")
        self.assertIsNone(path)
        self.assertIn("base64", err)


if __name__ == "__main__":
    unittest.main(verbosity=2)