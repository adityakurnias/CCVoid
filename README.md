# CCVoid

Personal XBPS package repository for Void Linux. Inspired by the [Voiders Community](https://git.voiders.dev/voiders-community), this project wraps the official `void-packages` build system into a single shell script that injects custom templates, builds packages, signs them with a repo key, and maintains a signed local repository.


## Usage

```sh
./builder <package_name>
```

Example:

```sh
./builder zed-editor
```

The script resets `void-packages`, copies your template into `srcpkgs/`,
builds, copies the `.xbps` into `repo/binpkgs/`, signs everything,
reindexes, and regenerates `packages.js` for the web page.

## Installing packages from this repo

Local checkout on the machine:

```sh
echo "repository=https://adityakurnias.github.io/CCVoid/" | sudo tee /etc/xbps.d/ccvoid.conf
sudo xbps-install -Sy
sudo xbps-install zed-editor
```

