#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091,SC2086,SC2016

set -xv

######################################################################################################################
### Setup Build System and GitHub

wget -qO- uny.nu/pkg | bash -s buildsys
mkdir /uny/tmp

### Installing build dependencies
unyp install openssl
unyp install libffi
unyp install python
pip3_bin=(/uny/pkg/python/*/bin/pip3)
"${pip3_bin[0]}" install setuptools
"${pip3_bin[0]}" install build

### Getting Variables from files
UNY_AUTO_PAT="$(cat UNY_AUTO_PAT)"
export UNY_AUTO_PAT
GH_TOKEN="$(cat GH_TOKEN)"
export GH_TOKEN

source /uny/uny/build/github_conf
source /uny/git/unypkg/fn

######################################################################################################################
### Timestamp & Download

uny_build_date_seconds_now="$(date +%s)"
uny_build_date_now="$(date -d @"$uny_build_date_seconds_now" +"%Y-%m-%dT%H.%M.%SZ")"

source /uny/uny/build/download_functions
mkdir -pv /uny/sources
cd /uny/sources || exit

pkgname="mercurial"
#pkggit="https://git.code.sf.net/p/mercurial/mercurial refs/tags/mercurial-*"
#gitdepth="--depth=1"

source_tarball_basename="$(
  wget -q --server-response https://mercurial-scm.org/release/ -O- 2>&1 | grep -o "mercurial-[0-9.]*.tar.gz" | sort -uV |
    tail -n 1
)"
source_tarball_url="https://mercurial-scm.org/release/$source_tarball_basename"
#source_folder_name="${source_tarball_basename//\.tar.*/}"
latest_ver="$(echo $source_tarball_basename | grep -oE "[0-9]*(([0-9]+\.)*[0-9]+)")"
latest_commit_id="$latest_ver"

### Get version info from git remote
#latest_head="$(git ls-remote --refs --tags --sort="v:refname" $pkggit | grep -E "mercurial-[0-9.]*$" | tail --lines=1)"
#latest_ver="$(echo "$latest_head" | grep -o "mercurial-[0-9.]*" | sed "s|mercurial-||")"
#latest_commit_id="$(echo "$latest_head" | cut --fields=1)"

version_details

# Release package no matter what:
echo "newer" >release-"$pkgname"

check_for_repo_and_create
#git_clone_source_repo

wget "$source_tarball_url"
tar xfz "$source_tarball_basename"
rm "$source_tarball_basename"
XZ_OPT="--threads=0" tar -cJpf "$pkgname-$latest_ver".tar.xz "$pkgname-$latest_ver"

######################################################################################################################
### Build

# unyc - run commands in uny's chroot environment
unyc <<"UNYEOF"
set -xv
source /uny/build/functions

pkgname="mercurial"

version_verbose_log_clean_unpack_cd
get_env_var_values
get_include_paths_temp

####################################################
### Start of individual build script

unset LD_RUN_PATH

make build

sed -i '138,142d' Makefile
TESTFLAGS="-j$(nproc) --tmpdir tmp" make check
pushd tests  &&
  rm -rf tmp &&
  ./run-tests.py --tmpdir tmp test-gpg.t
popd

make PREFIX=/uny/pkg/"$pkgname"/"$pkgver" install-bin

####################################################
### End of individual build script

add_to_paths_files
dependencies_file_and_unset_vars
cleanup_verbose_off_timing_end
UNYEOF

######################################################################################################################
### Packaging

package_unypkg
