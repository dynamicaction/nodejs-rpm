# nodejs22 RPM for Amazon Linux 2023

Builds a newer `nodejs22` RPM than Amazon Linux ships, for when a Node.js
security release lands before Amazon packages it. First used for 22.23.4
(PFM-4532).

The spec is Amazon's own (`dnf download --source nodejs22`), so the packages
match what the hosts already run: same package split, file layout and system
OpenSSL, zlib and libuv. The older kazuhisya-based branches (`v12.x` to
`v22.x`) stopped building at Node 22 (PFM-2529).

## Differences from Amazon's spec

- **Bundled brotli.** Amazon builds with `--shared-brotli`, which links the
  system brotli and ignores `deps/brotli`. Node's Brotli CVE fixes land in
  `deps/brotli`, so a shared build ships the version number without the fix.
- **Release `0.editedN`.** It sorts below Amazon's `-1` build of the same
  version. That alone does not move hosts to Amazon's build: shared-al2023 has
  repo priority 1 and dnf upgrades within the highest-priority repo first. To
  switch, pin Amazon's full version-release and delete ours from the repo.
- **Patches.** Amazon's patches that the target version does not yet contain.
  Each one's spec comment says when it can be dropped.

## Building a new version

On an x86_64 box with Docker (build1.dev1 works; use `sudo` for docker):

```bash
./prepare-sources.sh 22.23.5 ~/nodejs22-work
sudo ./build.sh 2023.12.20260803 ~/nodejs22-work
```

`prepare-sources.sh` downloads and verifies the Node.js tarball and ICU data,
sets every version macro in the spec from the source tree, and test-applies
the patches with `--fuzz=0`, as rpm does. It exits non-zero if a patch is
already upstream or no longer applies. Then:

1. Drop or rebase the failing patches in `nodejs22.spec`. Patches stack: check
   them in spec order, not one at a time.
2. Check whether the CVEs you are building for touch a `deps/` library the
   spec links from the system (`--shared-*` in `%build`). If so, bundle it.
3. Add a `%changelog` entry. Reset `baserelease` to `0.edited1` for a new
   version, or bump it to rebuild the same version.
4. Copy the updated spec back into this repo and commit it with the build.

Pass the releasever the target hosts pin (`hieradata/releasever/` in the
puppet repo), so the RPMs link against the same libraries.

## Publishing

Publish every runtime RPM (skip `debuginfo` and `debugsource`). dnf installs
`-docs` and `-full-i18n` as weak dependencies, so leaving them out pairs our
node with Amazon's older subpackages. Same procedure as PFM-1890; noarch RPMs
go in `x86_64/` too:

```bash
# on repo1.dev1 (Amazon Linux 2)
D=/srv/yum/shared-al2023/x86_64
sudo mv *.rpm $D/ && sudo chown jenkins:jenkins $D/nodejs22-*edited* $D/v8-*edited*
sudo su -s /bin/bash jenkins -c "createrepo --update $D/"
```

Then pin `nodejs::version` and `nodejs::npm_version` in the releasever
hieradata. Hosts refresh metadata within 120 s.
