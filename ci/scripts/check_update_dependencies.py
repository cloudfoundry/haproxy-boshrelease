#!/usr/bin/env python3
import functools
import json
import os
import re
import shutil
from dataclasses import dataclass
import subprocess
import sys
import textwrap
from typing import List, Optional, Tuple
import yaml

import github  # PyGithub
import requests
from packaging import version
from bs4 import BeautifulSoup
from git import Repo


# Required Environment Vars
BLOBSTORE_ACCESS_KEY_ID = os.environ["ACCESS_KEY_ID"]
BLOBSTORE_SECRET_ACCESS_KEY = os.environ["SECRET_ACCESS_KEY"]
gh = github.Github(login_or_token=os.environ["GITHUB_COM_TOKEN"])
# if DRY_RUN is set, blobs will not be uploaded and no PR created (downloads and local changes are still performed)
DRY_RUN = "DRY_RUN" in os.environ

# Other Global Variables
BLOBS_PATH = "config/blobs.yml"
PACKAGING_PATH = "packages/haproxy/packaging"


class BoshHelper:
    """
    Helper class to interface with the bosh-cli.
    """

    @classmethod
    def add_blob(cls, path, blobs_path):
        cls._run_bosh_cmd("add-blob", path, blobs_path)

    @classmethod
    def remove_blob(cls, path):
        cls._run_bosh_cmd("remove-blob", path)

    @classmethod
    def upload_blobs(cls):
        cls._run_bosh_cmd("upload-blobs")

    @classmethod
    def _run_bosh_cmd(cls, cmd, *args):
        cmd_params = ["bosh", cmd, *args]
        print(f"Running '{' '.join(cmd_params)}' ...")

        # run as subprocess and handle errors
        process = subprocess.Popen(cmd_params, stderr=subprocess.PIPE, stdout=subprocess.PIPE)
        stdout, stderr = process.communicate()
        if stdout:
            print(stdout.decode("utf-8"), file=sys.stdout)  # we don't expect any stdout under normal behaviour, might be useful for debugging though
        response = stderr.decode("utf-8")  # bosh writes success info to stderr for some reason
        if process.returncode != 0:
            raise Exception(f"bosh {cmd} failed. Aborting: {response}")
        # TODO: optional: bosh upload-blobs prints out the s3 URL for the uploaded blobs (captured in response here). Might be a nice addition to the PR description.


@dataclass
class Release:
    """
    A specific release (i.e. version) of a dependency.
    Currently, only the latest release of each dependency is fetched.
    """

    name: str
    url: str
    file: str
    version: version.Version

    def download(self) -> None:
        print(f"[{self.name}] download '{self.url}' to '{self.file}'")
        wget(self.url, self.file)

    def add_blob(self):
        # TODO: there's also keepalived/keepalived-2.2.7.tar.gz in blobs.yml do we need to auto-bump that as well? if so we need to extract the "haproxy/" path prefix into a variable
        target_path = "haproxy/" + self.file
        BoshHelper.add_blob(self.file, target_path)


@dataclass(repr=False)
class Dependency:
    """
    The base class that defines the interface of a dependency.
    fetch_latest_release needs to be implemented by subclasses.
    """

    name: str
    version_var_name: str
    pinned_version: str
    root_url: str

    _latest_release: Optional[Release] = None
    _current_version: version.Version = None

    @property
    def current_version(self) -> version.Version:
        """
        Fetches the current version of the release from the packaging file if not already known.
        (Should always be identical to the version in blobs.yml)
        """
        if self._current_version:
            return self._current_version
        with open(PACKAGING_PATH, "r") as packaging_file:  # TODO: extract filename to var?
            for line in packaging_file.readlines():
                if line.startswith(self.version_var_name):
                    # Regex: expecting e.g. "RELEASE_VERSION=1.2.3  # http://release.org/download". extracting Semver Group
                    rgx = rf"{self.version_var_name}=((?:[0-9]+\.){{1,3}}[0-9]+)\s+#.*$"
                    match = re.match(rgx, line)
                    if match:
                        current_version_str = match.groups()[0]
                        self._current_version = version.parse(current_version_str)
                        return self._current_version
            raise Exception(f"Could not find current version of {self.name}")

    @property
    def latest_release(self) -> Release:
        if not self._latest_release:
            self._latest_release = self.fetch_latest_release()
        return self._latest_release

    # fetch_latest_release is implemented by subclasses
    def fetch_latest_release(self) -> Release:
        """
        Dependency release tarballs/downloads are available from various locations (Github or custom websites),
        so fetching the latest release (incl. tarball download URL) has to be handled individually for every dependency.
        Therefore, fetch_latest_release is implemented by subclasses.
        """
        raise NotImplementedError

    def remove_current_blob(self):
        current_blob_path = f"haproxy/{self.name}-{self.current_version}.tar.gz"
        if self._check_blob_exists(current_blob_path):
            BoshHelper.remove_blob(current_blob_path)
        else:
            raise Exception(f"Current Blob not found: {current_blob_path}")

    def _check_blob_exists(self, blob_path) -> bool:
        """
        Checks config/blobs.yml if blob exists
        """
        with open(BLOBS_PATH, "r") as blobs_file:
            yml = yaml.safe_load(blobs_file)
            return blob_path in yml.keys()

    def update_packaging_file(self):
        """
        Writes the new dependency version and download-url into packages/haproxy/packaging
        """
        with open(PACKAGING_PATH, "r") as packaging_file:
            replacement = ""
            for line in packaging_file.readlines():
                if line.startswith(self.version_var_name):
                    line = f"{self.version_var_name}={self.latest_release.version}  # {self.latest_release.url}\n"
                replacement += line

        with open(PACKAGING_PATH, "w") as packaging_file_write:
            packaging_file_write.write(replacement)

    def create_pr(self):
        local_git = Repo(os.curdir).git
        remote_repo = gh.get_repo("cloudfoundry/haproxy-boshrelease")
        pr_branch = f"{self.name}-auto-bump"

        # Create commit
        print(f"[{self.name}] Creating git commit...")
        local_git.add(PACKAGING_PATH)
        local_git.add(BLOBS_PATH)
        local_git.commit("-m", f"Bump {self.name} to {self.latest_release.version}")
        if not DRY_RUN:
            local_git.push("origin", pr_branch)

        # create PR
        print("Creating pull request...")
        pr_body = textwrap.dedent(
            f"""
            Automatic bump from version {self.current_version} to version {self.latest_release.version}, downloaded from {self.latest_release.url}.

            After merge, consider releasing a new version of haproxy-boshrelease.
        """
        )

        if not DRY_RUN:
            remote_repo.create_pull(
                title=f"Bump {self.name} version to {self.latest_release.version}",
                body=pr_body,
                base="master",
                head="cloudfoundry:" + pr_branch,
            )


@dataclass
class GithubDependency(Dependency):
    tagname_prefix: str = None

    def fetch_latest_release(self) -> Release:
        repo_org_and_name = self.root_url.lstrip("https://github.com/")  # TODO: linter very much not happy with that
        repo = gh.get_repo(repo_org_and_name)
        releases = repo.get_releases()

        latest_release = None
        latest_version = version.parse("0.0.0")

        for rel in releases:
            current_raw = rel.tag_name.lstrip(self.tagname_prefix)
            current_version = version.parse(current_raw)
            if latest_version < current_version and current_raw.startswith(self.pinned_version):
                latest_version = current_version
                latest_release = Release(rel.body, rel.tarball_url, f"{self.name}-{str(current_version)}.tar.gz", current_version)

        if latest_version == version.parse("0.0.0"):
            raise Exception(f"No release found for '{repo}'")

        return latest_release


@dataclass
class SocatDependency(Dependency):
    def fetch_latest_release(self) -> Release:
        releases = []

        data = requests.get(self.root_url)
        html = BeautifulSoup(data.text, "html.parser")
        source_code_table = html.find("table")
        rows = source_code_table.find_all("tr")

        # read HTML table
        for row in rows:
            cols = row.find_all("td")
            cols = [ele.text.strip() for ele in cols]
            if len(cols) > 0:  # Get rid of empty header row
                releases.append([ele for ele in cols if ele])  # Get rid of empty values

        if len(releases) == 0:
            raise Exception(f"Failed to parse Socat Releases from {self.root_url}")

        # Regex: Match only releases beginning with pinned version
        rgx = fr"socat-(" + self.pinned_version + r"(?:\.[0-9]){2})\.tar\.gz"
        # Iterate over found releases, pick latest version
        latest_version = version.parse("0.0.0")
        latest_release = None
        for release in releases:
            release_file_name = release[0]
            # Ignore Table Headers/irrelevant Rows
            if release_file_name in ["Parent Directory", "Archive/"]:
                continue

            match = re.match(rgx, release_file_name)
            if match:
                current_version = version.parse(match.groups()[0])  # TODO: cleaner possible?
                if current_version > latest_version:
                    latest_release = Release(
                        release_file_name.rstrip(".tar.gz"), f"{self.root_url}/{release_file_name}", release_file_name, current_version
                    )
                    latest_version = current_version

        if latest_version == version.parse("0.0.0"):
            raise Exception(f"Failed to get latest socat version from {self.root_url}")

        return latest_release


@dataclass
class HaproxyDependency(Dependency):
    def __post_init__(self):
        # This takes care of version pinning (only releases of pinned version in releases.json/directory)
        self.root_url = self.root_url.format(self.pinned_version)

    def fetch_latest_release(self) -> Release:
        releases_json_url = f"{self.root_url}/releases.json"
        resp = requests.get(releases_json_url)
        if resp.status_code != 200:
            raise Exception("Failed to get HAProxy releases list")
        releases_json = json.loads(resp.text)
        latest_version = releases_json["latest_release"]
        latest_release = releases_json["releases"][latest_version]

        download_url = f"{self.root_url}/{latest_release['file']}"
        return Release(latest_release["file"].rstrip(".tar.gz"), download_url, latest_release["file"], version.parse(latest_version))


def wget(url: str, path: str, auth: Optional[Tuple[str, str]] = None):
    """
    downloads a file, optionally decoding any compression applied on HTTP level
    """
    with requests.get(url, stream=True, allow_redirects=True, auth=auth) as resp:
        if resp.status_code != 200:
            raise Exception(f"request failed {resp.status_code}")
        # see https://github.com/psf/requests/issues/2155#issuecomment-50771010
        resp.raw.read = functools.partial(resp.raw.read, decode_content=True)
        with open(path, "wb") as file:
            shutil.copyfileobj(resp.raw, file)


def write_private_yaml():
    """
    Writes private.yml to config subdirectory (used for blobstore/s3 authentication)
    """
    private_yml = {
        "blobstore": {
            "options": {
                "access_key_id": BLOBSTORE_ACCESS_KEY_ID,
                "secret_access_key": BLOBSTORE_SECRET_ACCESS_KEY,
            }
        }
    }
    with open("config/private.yml", "w") as file:
        yaml.dump(private_yml, file, default_flow_style=False)


def cleanup_local_changes():
    # TODO: switch to master (force if necessary)
    # TODO: clean untracked files (e.g. release tarballs). Keep config/private.yml!
    pass


def main() -> None:
    dependencies: List[Dependency] = [
        HaproxyDependency("haproxy", "HAPROXY_VERSION", "2.5", "http://www.haproxy.org/download/{}/src"),
        SocatDependency("socat", "SOCAT_VERSION", "1.7", "http://www.dest-unreach.org/socat/download"),
        GithubDependency("lua", "LUA_VERSION", "5.4", "https://github.com/lua/lua", tagname_prefix="v"),
        GithubDependency("pcre2", "PCRE_VERSION", "10", "https://github.com/PCRE2Project/pcre2", tagname_prefix="pcre2-"),
        # TODO: What about keepalived/keepalived-2.2.7.tar.gz?
    ]

    write_private_yaml()

    for dependency in dependencies:
        current_version = dependency.current_version
        latest_release = dependency.latest_release
        latest_version = latest_release.version

        if latest_version > current_version:
            print(f"[{dependency.name}] Version-Bump required: {current_version} --> {latest_version}")
            latest_release.download()
            dependency.remove_current_blob()
            latest_release.add_blob()
            dependency.update_packaging_file()
            if not DRY_RUN:
                BoshHelper.upload_blobs()
            dependency.create_pr()  # TODO: untested

            # in case more deps need to be bumped
            cleanup_local_changes()  # TODO: not implemented


if __name__ == "__main__":
    main()
