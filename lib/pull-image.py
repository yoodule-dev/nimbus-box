#!/usr/bin/env python3
'''Unpack an OCI/Docker registry image into a directory - no Docker, no root.

usage: pull-image.py IMAGE_REF DEST [ARCH]
  IMAGE_REF  e.g. ghcr.io/yoodule/nimbus/gateway:v1.2.2  or  redis:7.4.1-bookworm
  ARCH       amd64 | arm64 (default: this machine)
Re-running is a no-op when DEST already holds the same image digest.
'''
import json, os, platform, re, shutil, subprocess, sys, tempfile, time, urllib.error, urllib.request

ACCEPT = ','.join([
    'application/vnd.oci.image.index.v1+json',
    'application/vnd.docker.distribution.manifest.list.v2+json',
    'application/vnd.oci.image.manifest.v1+json',
    'application/vnd.docker.distribution.manifest.v2+json'])


def parse(ref):
    ref, _, digest = ref.partition('@')
    name, tag = ref, 'latest'
    if ':' in ref.rsplit('/', 1)[-1]:
        name, tag = ref.rsplit(':', 1)
    parts = name.split('/')
    if len(parts) > 1 and ('.' in parts[0] or ':' in parts[0] or parts[0] == 'localhost'):
        registry, repo = parts[0], '/'.join(parts[1:])
    else:
        registry, repo = 'registry-1.docker.io', name
        if '/' not in repo:
            repo = 'library/' + repo
    if registry in ('docker.io', 'index.docker.io'):
        registry = 'registry-1.docker.io'
    return registry, repo, (digest or tag)


def http(url, token=None, accept=None):
    h = {}
    if token:
        h['Authorization'] = 'Bearer ' + token
    if accept:
        h['Accept'] = accept
    return urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=120)


def get_token(registry, repo):
    try:
        http('https://%s/v2/' % registry)
        return None
    except urllib.error.HTTPError as e:
        if e.code != 401:
            raise
        fields = dict(re.findall(r'(\w+)="([^"]*)"', e.headers.get('WWW-Authenticate', '')))
        if 'realm' not in fields:
            raise
        q = 'service=%s&scope=repository:%s:pull' % (fields.get('service', ''), repo)
        d = json.load(http(fields['realm'] + '?' + q))
        return d.get('token') or d.get('access_token')


def manifest(registry, repo, ref, token):
    return json.load(http('https://%s/v2/%s/manifests/%s' % (registry, repo, ref), token, ACCEPT))


def curl(url, token, out=None):
    # curl drops the Authorization header on cross-host redirects (CDN), urllib does not.
    cmd = ['curl', '-fsSL', '--retry', '3', '--retry-delay', '2']
    if token:
        cmd += ['-H', 'Authorization: Bearer ' + token]
    if out:
        cmd += ['-o', out]
    r = subprocess.run(cmd + [url], stdout=None if out else subprocess.PIPE)
    if r.returncode != 0:
        sys.exit('download failed: ' + url)
    return r.stdout


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    ref, dest = sys.argv[1], os.path.abspath(sys.argv[2]).rstrip('/')
    arch = sys.argv[3] if len(sys.argv) > 3 else {'x86_64': 'amd64', 'aarch64': 'arm64'}.get(platform.machine(), platform.machine())
    registry, repo, r = parse(ref)
    t0 = time.time()
    token = get_token(registry, repo)
    m = manifest(registry, repo, r, token)
    if 'manifests' in m:
        pick = [x for x in m['manifests'] if x.get('platform', {}).get('os') == 'linux' and x['platform'].get('architecture') == arch]
        if not pick:
            sys.exit('no linux/%s build of %s' % (arch, ref))
        mdigest = pick[0]['digest']
        m = manifest(registry, repo, mdigest, token)
    else:
        mdigest = r
    marker = os.path.join(dest, '.pulled')
    if os.path.exists(marker) and open(marker).read().strip() == mdigest:
        print('up to date: %s' % ref)
        return
    base = 'https://%s/v2/%s/blobs/' % (registry, repo)
    shutil.rmtree(dest, ignore_errors=True)
    os.makedirs(dest)
    open(dest + '.config.json', 'wb').write(curl(base + m['config']['digest'], token))
    n = len(m['layers'])
    print('%s: %d layers, %.0f MB' % (ref, n, sum(l['size'] for l in m['layers']) / 1e6), flush=True)
    for i, layer in enumerate(m['layers'], 1):
        if 'zstd' in layer.get('mediaType', '') and not shutil.which('zstd'):
            sys.exit('layer is zstd-compressed but zstd is not installed')
        if time.time() - t0 > 240:          # registry tokens are short-lived
            token, t0 = get_token(registry, repo), time.time()
        print('[%d/%d] %s %.1fMB' % (i, n, layer['digest'][7:19], layer['size'] / 1e6), flush=True)
        stage = tempfile.mkdtemp(dir=os.path.dirname(dest))
        blob = os.path.join(stage, 'layer')
        curl(base + layer['digest'], token, blob)
        ex = os.path.join(stage, 'x')
        os.makedirs(ex)
        # Only skip the TOP-LEVEL dev/ (device nodes). An unanchored dev/* also drops
        # nested dirs like next/dist/server/dev/ and breaks apps.
        subprocess.run(['tar', '-xf', blob, '-C', ex, '--no-same-owner', '-p', '--anchored', '--exclude=dev/*'], stderr=subprocess.DEVNULL)
        os.remove(blob)
        for p in (ex, dest):
            subprocess.run(['chmod', '-R', 'u+rwX', p], stderr=subprocess.DEVNULL)
        for root, dirs, files in os.walk(ex):          # apply OCI whiteouts
            rel = os.path.relpath(root, ex)
            tdir = os.path.join(dest, rel)
            for f in list(files):
                p = os.path.join(root, f)
                if f == '.wh..wh..opq':
                    if os.path.isdir(tdir):
                        for e in os.listdir(tdir):
                            t = os.path.join(tdir, e)
                            shutil.rmtree(t) if os.path.isdir(t) and not os.path.islink(t) else os.remove(t)
                    os.remove(p)
                elif f.startswith('.wh.'):
                    t = os.path.join(tdir, f[4:])
                    if os.path.islink(t) or os.path.isfile(t):
                        os.remove(t)
                    elif os.path.isdir(t):
                        shutil.rmtree(t)
                    os.remove(p)
        subprocess.run(['cp', '-a', '--remove-destination', ex + '/.', dest + '/'], stderr=subprocess.DEVNULL)
        shutil.rmtree(stage, ignore_errors=True)
    open(marker, 'w').write(mdigest)
    print('DONE', flush=True)


main()
