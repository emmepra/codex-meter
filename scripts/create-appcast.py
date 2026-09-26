#!/usr/bin/env python3
"""Sign one update archive and its feed with the project key in macOS Keychain."""
import argparse, pathlib, re, subprocess, xml.etree.ElementTree as ET
p = argparse.ArgumentParser()
p.add_argument('version'); p.add_argument('archive', type=pathlib.Path); p.add_argument('output', type=pathlib.Path)
p.add_argument('--download-url') # Supports isolated local update smoke tests.
a = p.parse_args()
assert re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', a.version)
root = pathlib.Path(__file__).resolve().parent.parent
tools = root / '.build/sparkle-2.10.0/bin'
account = 'it.emmepra.codex-meter'
public = subprocess.check_output([str(tools/'generate_keys'), '--account', account, '-p'], text=True).strip()
assert public == (root/'Resources/Sparkle-public-key.txt').read_text().strip(), 'Signing key does not match the embedded public key'
signer = [str(tools/'sign_update'), '--account', account]
signature = subprocess.check_output(signer + ['-p', str(a.archive)], text=True).strip()
subprocess.run(signer + ['--verify', str(a.archive), signature], check=True)
ns = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', ns)
feed = ET.Element('rss', {'version':'2.0'})
channel = ET.SubElement(feed, 'channel')
ET.SubElement(channel, 'title').text = 'Codex Meter updates'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = 'Codex Meter ' + a.version
ET.SubElement(item, '{'+ns+'}minimumSystemVersion').text = '13.0'
ET.SubElement(item, '{'+ns+'}version').text = a.version
ET.SubElement(item, '{'+ns+'}shortVersionString').text = a.version
url = a.download_url or f'https://github.com/emmepra/codex-meter/releases/download/v{a.version}/Codex-Meter-{a.version}-macos-arm64.zip'
ET.SubElement(item, 'enclosure', {'url':url, 'length':str(a.archive.stat().st_size), 'type':'application/octet-stream', '{'+ns+'}edSignature':signature})
ET.ElementTree(feed).write(a.output, encoding='utf-8', xml_declaration=True)
subprocess.run(signer + [str(a.output)], check=True)
subprocess.run(signer + ['--verify', str(a.output)], check=True)
