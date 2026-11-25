#!/usr/bin/env python3
"""Extract the files of a public container image without Docker (Python standard library only).

  oci_extract.py <registry>/<repository>:<tag> <dest dir> [path prefix [path ...]]

Downloads the image's layers (anonymous pull token; checked against their sha256 digests) and
unpacks them in order into <dest dir>. With a path prefix (e.g. srv/srcds) only that subtree is
extracted, with the prefix removed; with paths after it, only those files (relative to the
prefix). Meant for the files-only srcds:<game>-windows images
(docker/srcds/Dockerfile, target windows), which Windows runners can't pull with Docker because
they are Linux images. Whiteout files are honoured.
"""
import hashlib
import json
import os
import shutil
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request

ACCEPT = ', '.join((
    'application/vnd.oci.image.index.v1+json',
    'application/vnd.oci.image.manifest.v1+json',
    'application/vnd.docker.distribution.manifest.list.v2+json',
    'application/vnd.docker.distribution.manifest.v2+json',
))


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def request(url, token=None, accept=None):
    """GET url; follows a redirect (blob storage) without sending the registry token along."""
    headers = {'User-Agent': 'oci-extract'}
    if token:
        headers['Authorization'] = f'Bearer {token}'
    if accept:
        headers['Accept'] = accept
    opener = urllib.request.build_opener(NoRedirect)
    try:
        return opener.open(urllib.request.Request(url, headers=headers), timeout=120)
    except urllib.error.HTTPError as error:
        if error.code in (301, 302, 303, 307, 308):
            location = error.headers['Location']
            return urllib.request.urlopen(
                urllib.request.Request(location, headers={'User-Agent': 'oci-extract'}),
                timeout=120)
        raise


def manifest_for(registry, repository, reference, token):
    with request(f'https://{registry}/v2/{repository}/manifests/{reference}', token, ACCEPT) as r:
        data = json.load(r)
    if 'manifests' in data:      # an index: take linux/amd64, else the first entry
        entries = data['manifests']
        chosen = next((m for m in entries if m.get('platform', {}).get('os') == 'linux'
                       and m.get('platform', {}).get('architecture') == 'amd64'), entries[0])
        return manifest_for(registry, repository, chosen['digest'], token)
    return data


def safe_join(root, name):
    path = os.path.normpath(os.path.join(root, name))
    if os.path.commonpath([os.path.abspath(root), os.path.abspath(path)]) != os.path.abspath(root):
        raise ValueError(f'unsafe path in layer: {name}')
    return path


def extract_layer(path, dest, prefix, only=()):
    with tarfile.open(path) as tar:
        for member in tar:
            name = member.name.lstrip('./')
            if prefix:
                if name != prefix and not name.startswith(prefix + '/'):
                    continue
                name = name[len(prefix):].lstrip('/')
                if not name:
                    continue
            if only and name not in only:
                continue
            directory, base = os.path.split(name)
            if base.startswith('.wh.'):          # whiteout: delete from earlier layers
                target = safe_join(dest, os.path.join(directory, base[4:]))
                if base == '.wh..wh..opq':
                    target = safe_join(dest, directory)
                    for child in os.listdir(target) if os.path.isdir(target) else ():
                        child = os.path.join(target, child)
                        shutil.rmtree(child) if os.path.isdir(child) else os.remove(child)
                elif os.path.isdir(target):
                    shutil.rmtree(target)
                elif os.path.lexists(target):
                    os.remove(target)
                continue
            target = safe_join(dest, name)
            if member.isdir():
                os.makedirs(target, exist_ok=True)
            elif member.isfile():
                os.makedirs(os.path.dirname(target), exist_ok=True)
                with tar.extractfile(member) as src, open(target, 'wb') as out:
                    shutil.copyfileobj(src, out, 1 << 20)
                if member.mode & 0o111:
                    os.chmod(target, 0o755)
            # links and devices are not needed for the server files and are skipped


def main(ref, dest, prefix='', *only):
    registry, _, rest = ref.partition('/')
    repository, _, tag = rest.rpartition(':') if ':' in rest.rsplit('/', 1)[-1] else (rest, '', 'latest')
    with request(f'https://{registry}/token?scope=repository:{repository}:pull') as r:
        token = json.load(r)['token']
    manifest = manifest_for(registry, repository, tag, token)
    os.makedirs(dest, exist_ok=True)
    prefix = prefix.strip('/')
    for layer in manifest['layers']:
        digest = layer['digest']
        algorithm, expected = digest.split(':', 1)
        print(f'   layer {digest[:19]} {layer.get("size", 0) / 1e6:.0f} MB', flush=True)
        sha = hashlib.new(algorithm)
        with tempfile.NamedTemporaryFile(delete=False) as tmp:
            with request(f'https://{registry}/v2/{repository}/blobs/{digest}', token) as r:
                while chunk := r.read(1 << 20):
                    sha.update(chunk)
                    tmp.write(chunk)
        try:
            if sha.hexdigest() != expected:
                raise SystemExit(f'{digest}: downloaded data has {algorithm} {sha.hexdigest()}')
            extract_layer(tmp.name, dest, prefix, set(only))
        finally:
            os.remove(tmp.name)


if __name__ == '__main__':
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    main(*sys.argv[1:])
