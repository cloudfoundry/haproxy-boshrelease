#!/usr/bin/env python3
import functools
import json
import os
import re
import shutil
from dataclasses import dataclass
import subprocess
import sys
from typing import List, Optional, Tuple
import yaml

import github  # PyGithub
import requests
from packaging import version
from bs4 import BeautifulSoup

BLOBSTORE_ACCESS_KEY_ID = os.environ["ACCESS_KEY_ID"]
BLOBSTORE_SECRET_ACCESS_KEY = os.environ["SECRET_ACCESS_KEY"]

gh = github.Github(login_or_token=os.environ["GITHUB_COM_TOKEN"])

DRY_RUN = "DRY_RUN" in os.environ


def main() -> None:
    dependencies: List[Dependency] = [
        HaproxyDependency("haproxy", "HAPROXY_VERSION", "2.5", "http://www.haproxy.org/download/{}/src"),
        SocatDependency("socat", "SOCAT_VERSION", "1.7", "http://www.dest-unreach.org/socat/download"),
        GithubDependency("lua", "LUA_VERSION", "5.4", "https://github.com/lua/lua", tagname_prefix="v"),
        GithubDependency("pcre2", "PCRE_VERSION", "10", "https://github.com/PCRE2Project/pcre2", tagname_prefix="pcre2-"),
    ]

    # setup private.yml for blobstore/s3 authentication
    write_private_yaml()

    for dependency in dependencies:
        current_version = dependency.current_version
        latest_release = dependency.latest_release
        latest_version = latest_release.version

        if latest_version > current_version:
            print(f"bump required: {current_version} --> {latest_version}")
            latest_release.download()
            dependency.remove_current_blob()
            latest_release.add_blob()
            dependency.update_packaging_file()
            BoshHelper.upload_blobs()

            # TODO: create PR
            # TODO: cleanup (in case more deps need to be bumped)


class BoshHelper:
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

        if not DRY_RUN:
            # run as subprocess and handle errors
            process = subprocess.Popen(cmd_params, stderr=subprocess.PIPE, stdout=subprocess.PIPE)
            stdout, stderr = process.communicate()
            if stdout:
                print(
                    stdout.decode("utf-8"), file=sys.stdout
                )  # we don't expect any stdout under normal behaviour, might be useful for debugging though
            response = stderr.decode("utf-8")  # bosh writes success info to stderr for some reason
            if process.returncode != 0:
                raise Exception(f"bosh {cmd} failed. Aborting: {response}")


@dataclass
class Release:

    name: str
    url: str
    file: str
    version: version.Version

    def download(self) -> None:
        path = f"./" + self.file

        print(f"[{self.name}] download '{self.url}' to '{path}'")
        if not DRY_RUN:
            wget(self.url, path)

    def add_blob(self):
        target_path = "haproxy/" + self.file
        BoshHelper.add_blob(self.file, target_path)


@dataclass(repr=False)
class Dependency:
    """
    The base class that defines the interface of a dependency. It is mainly a data
    structure to hold all related values of a dependency.
    """

    name: str
    version_var_name: str
    pinned_version: str
    root_url: str

    # override the file name, will be templated with the version
    file: Optional[str] = None
    # whether to strip any leading 'v's from the release version
    strip_v: bool = False

    _latest_release: Optional[Release] = None

    @property
    def current_version(self) -> version.Version:
        with open("packages/haproxy/packaging", "r") as packaging_file:  # TODO: extract filename to var?
            for line in packaging_file.readlines():
                if line.startswith(self.version_var_name):
                    current_version_str = line.split("=")[1]
                    return version.parse(current_version_str)

    @property
    def latest_release(self) -> Release:
        if not self._latest_release:
            self._latest_release = self.fetch_latest_release()
        return self._latest_release

    def fetch_latest_release(self) -> Release:
        raise NotImplementedError

    def remove_current_blob(self):
        current_blob_path = f"haproxy/{self.name}-{self.current_version}.tar.gz"
        if self._check_blob_exists(current_blob_path):
            BoshHelper.remove_blob(current_blob_path)
        else:
            raise Exception(f"Current Blob not found: {current_blob_path}")
        pass

    def _check_blob_exists(self, blob_path) -> bool:
        with open("./config/blobs.yml", "r") as blobs_file:
            yml = yaml.safe_load(blobs_file)
            return blob_path in yml.keys()

    def update_packaging_file(self):
        # TODO: remove superfluous comments in packaging file (line above version)
        with open("packages/haproxy/packaging", "r") as packaging_file:
            replacement = ""
            for line in packaging_file.readlines():
                if line.startswith(self.version_var_name):
                    line = f"{self.version_var_name}={self.latest_release.version} # {self.latest_release.url}\n"
                replacement += line

        with open("packages/haproxy/packaging", "w") as packaging_file_write:
            packaging_file_write.write(replacement)


@dataclass
class GithubDependency(Dependency):
    tagname_prefix: str = None

    def fetch_latest_release(self) -> Release:
        repo_org_and_name = self.root_url.lstrip("https://github.com/")
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

        return latest_release


@dataclass
class HaproxyDependency(Dependency):
    def __post_init__(self):
        # This takes care of version pinning (only releases of pinned version in releases.json/directory)
        self.root_url = self.root_url.format(self.pinned_version)

    def fetch_latest_release(self) -> Release:
        releases_json_url = f"{self.root_url}/releases.json"
        resp = requests.get(releases_json_url)
        releases_json = json.loads(resp.text)
        latest_version = releases_json["latest_release"]
        latest_release = releases_json["releases"][latest_version]

        download_url = f"{self.root_url}/{latest_release['file']}"
        return Release(latest_release["file"].rstrip(".tar.gz"), download_url, latest_release["file"], version.parse(latest_version))


def wget(url: str, path: str, auth: Optional[Tuple[str, str]] = None):
    """
    downloads a file, optionally decoding any compression applied on HTTP level
    """
    with requests.get(url, stream=True, allow_redirects=True, auth=auth) as r:
        if r.status_code != 200:
            raise Exception(f"request failed {r.status_code}")
        # see https://github.com/psf/requests/issues/2155#issuecomment-50771010
        r.raw.read = functools.partial(r.raw.read, decode_content=True)
        with open(path, "wb") as f:
            shutil.copyfileobj(r.raw, f)


def write_private_yaml():
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


if __name__ == "__main__":
    main()


# TODO: logging
# TODO: error-handling
