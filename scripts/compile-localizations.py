#!/usr/bin/env python3
"""Compile the shared String Catalog for SwiftPM and Xcode, without requiring Xcode's catalog tool."""
import argparse
import json
import plistlib
from pathlib import Path

root = Path(__file__).resolve().parents[1]
catalog = json.loads((root / 'Packages/RunCore/Localization/Localizable.xcstrings').read_text())
parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true', help='Fail if committed resources are stale')
args = parser.parse_args()
for language in ('en', 'de'):
    strings, plurals = {}, {}
    for key, entry in sorted(catalog['strings'].items()):
        localization = entry['localizations'][language]
        if 'stringUnit' in localization:
            strings[key] = localization['stringUnit']['value']
        else:
            forms = localization['variations']['plural']
            plurals[key] = {
                'NSStringLocalizedFormatKey': '%#@count@',
                'count': {'NSStringFormatSpecTypeKey': 'NSStringPluralRuleType',
                          'NSStringFormatValueTypeKey': 'ld',
                          **{form: value['stringUnit']['value'] for form, value in forms.items()}}
            }
    directory = root / f'Packages/RunCore/Sources/RunCore/Resources/{language}.lproj'
    rendered = '\n'.join(f'{json.dumps(k,ensure_ascii=False)} = {json.dumps(v,ensure_ascii=False)};' for k,v in strings.items()) + '\n'
    outputs = {'Localizable.strings': rendered.encode(),
               'Localizable.stringsdict': plistlib.dumps(plurals, sort_keys=True)}
    for name, content in outputs.items():
        target = directory / name
        if args.check:
            if not target.exists() or target.read_bytes() != content:
                raise SystemExit(f'Stale localization resource: {target.relative_to(root)}')
        else:
            directory.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
print(f"Verified {len(catalog['strings'])} English/German catalog entries" if args.check else 'Compiled English/German resources')
