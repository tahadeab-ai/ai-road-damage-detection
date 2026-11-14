#!/usr/bin/env python3
"""
Patch tflite_flutter package in pub-cache for compatibility with modern Dart (Dart 3.7+ / Flutter 3.29+).
Resolves:
1. 'UnmodifiableUint8ListView' removed in newer Dart SDK -> use .asUnmodifiableView()
2. Undefined name 'TfLiteType' in byte_conversion_utils.dart -> import & export tensorflow_lite_bindings_generated.dart
"""

import glob
import os
import re
import sys

def patch_pub_cache():
    cache_roots = [
        os.path.expanduser("~/.pub-cache"),
        os.path.expanduser("~/AppData/Local/Pub/Cache"),
    ]
    env_cache = os.environ.get("PUB_CACHE")
    if env_cache:
        cache_roots.insert(0, env_cache)

    patched_count = 0
    for root in cache_roots:
        if not os.path.exists(root):
            continue

        # 1. Patch tensor.dart
        for p in glob.glob(os.path.join(root, "hosted/**/tflite_flutter-*/lib/src/tensor.dart"), recursive=True):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    content = f.read()
                new_content = re.sub(
                    r"return\s+UnmodifiableUint8ListView\s*\(\s*([\s\S]*?)\s*\);",
                    r"return \1.asUnmodifiableView();",
                    content,
                )
                if new_content != content:
                    with open(p, "w", encoding="utf-8") as f:
                        f.write(new_content)
                    print(f"Patched tensor.dart: {p}")
                    patched_count += 1
            except Exception as e:
                print(f"Warning patching {p}: {e}")

        # 2. Patch byte_conversion_utils.dart
        for p in glob.glob(os.path.join(root, "hosted/**/tflite_flutter-*/lib/src/util/byte_conversion_utils.dart"), recursive=True):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    content = f.read()
                if "tensorflow_lite_bindings_generated.dart" not in content:
                    new_content = "import 'package:tflite_flutter/src/bindings/tensorflow_lite_bindings_generated.dart';\n" + content
                    with open(p, "w", encoding="utf-8") as f:
                        f.write(new_content)
                    print(f"Patched byte_conversion_utils.dart: {p}")
                    patched_count += 1
            except Exception as e:
                print(f"Warning patching {p}: {e}")

        # 3. Patch tflite_flutter.dart
        for p in glob.glob(os.path.join(root, "hosted/**/tflite_flutter-*/lib/tflite_flutter.dart"), recursive=True):
            try:
                with open(p, "r", encoding="utf-8") as f:
                    content = f.read()
                # Remove any accidentally appended export at bottom
                content = content.replace("\nexport 'src/bindings/tensorflow_lite_bindings_generated.dart';\n", "\n")
                if "tensorflow_lite_bindings_generated.dart" not in content:
                    target = "export 'src/delegate.dart';"
                    replacement = "export 'src/delegate.dart';\nexport 'src/bindings/tensorflow_lite_bindings_generated.dart';"
                    new_content = content.replace(target, replacement)
                    with open(p, "w", encoding="utf-8") as f:
                        f.write(new_content)
                    print(f"Patched tflite_flutter.dart: {p}")
                    patched_count += 1
            except Exception as e:
                print(f"Warning patching {p}: {e}")

    print(f"Patch complete. Total files modified: {patched_count}")

if __name__ == "__main__":
    patch_pub_cache()
