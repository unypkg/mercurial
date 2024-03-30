#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091,SC2086,SC2016

set -xv

######################################################################################################################
### Setup Build System and GitHub

wget -qO- uny.nu/pkg | bash -s buildsys
mkdir /uny/tmp

### Getting Variables from files
UNY_AUTO_PAT="$(cat UNY_AUTO_PAT)"
export UNY_AUTO_PAT
GH_TOKEN="$(cat GH_TOKEN)"
export GH_TOKEN

source /uny/uny/build/github_conf

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

### Check if the build should be continued
#version_details
#[[ ! -f /uny/sources/vdet-"$pkgname"-new ]] && echo "No newer version needs to be built." && exit
{
    echo "$latest_ver"
    echo "$latest_commit_id"
    echo "$uny_build_date_now"
    echo "$uny_build_date_seconds_now"
} >vdet-"$pkgname"-new

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

cd /uny/pkg || exit
for pkg in /uny/sources/vdet-*-new; do
    vdet_content="$(cat "$pkg")"
    vdet_new_file="$pkg"
    pkg="$(echo "$pkg" | grep -Eo "vdet.*new$" | sed -e "s|vdet-||" -e "s|-new||")"
    pkgv="$(echo "$vdet_content" | head -n 1)"

    cp "$vdet_new_file" "$pkg"/"$pkgv"/vdet

    source_archive_orig="$(echo /uny/sources/"$pkg"-"$pkgv".tar.*)"
    source_archive_new="$(echo "$source_archive_orig" | sed -r -e "s|^.*/||" -e "s|(\.tar.*$)|-source\1|")"
    cp -a "$source_archive_orig" "$source_archive_new"
    cp -a /uny/uny/build/logs/"$pkg"-*.log "$pkg"-build.log
    XZ_OPT="-9 --threads=0" tar -cJpf unypkg-"$pkg".tar.xz "$pkg"

    gh -R unypkg/"$pkg" release create "$pkgv"-"$uny_build_date_now" --generate-notes \
        "$pkg/$pkgv/vdet#vdet - $vdet_content" unypkg-"$pkg".tar.xz "$pkg"-build.log "$source_archive_new"
done
