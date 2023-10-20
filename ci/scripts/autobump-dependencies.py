#!/usr/bin/env python3
import functools
from hashlib import sha1
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
BLOBSTORE_SECRET_ACCESS_KEY = os.environ["GCP_SERVICE_KEY"]
gh = github.Github(login_or_token=os.environ["GITHUB_COM_TOKEN"])
PR_ORG = os.environ["PR_ORG"]
PR_BASE = os.environ["PR_BASE"]
PR_LABEL = os.environ["PR_LABEL"]
# if DRY_RUN is set, blobs will not be uploaded and no PR created (downloads and local changes are still performed)
DRY_RUN = "DRY_RUN" in os.environ

# Other Global Variables
BLOBS_PATH = "config/blobs.yml"
PACKAGING_PATH = "packages/{}/packaging"


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
        if stderr:
            print(stderr.decode("utf-8"), file=sys.stdout)
        if process.returncode != 0:
            raise Exception(f"Command {' '.join(cmd_params)} failed. Aborting.")


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

    def add_blob(self, package):
        target_path = f"{package}/{self.file}"
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
    package: str = "haproxy"
    remote_repo = gh.get_repo(f"{PR_ORG}/haproxy-boshrelease")

    _latest_release: Optional[Release] = None
    _current_version: version.Version = None

    @property
    def pr_branch(self):
        return f"{self.name}-auto-bump-{PR_BASE}"

    @property
    def current_version(self) -> version.Version:
        """
        Fetches the current version of the release from the packaging file if not already known.
        (Should always be identical to the version in blobs.yml)
        """
        if self._current_version:
            return self._current_version
        with open(PACKAGING_PATH.format(self.package), "r") as packaging_file:
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
        current_blob_path = f"{self.package}/{self.name}-{self.current_version}.tar.gz"
        if self._check_blob_exists(current_blob_path):
            BoshHelper.remove_blob(current_blob_path)
        else:
            print(f"Current Blob not found: {current_blob_path}")

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
        with open(PACKAGING_PATH.format(self.package), "r") as packaging_file:
            replacement = ""
            for line in packaging_file.readlines():
                if line.startswith(self.version_var_name):
                    line = f"{self.version_var_name}={self.latest_release.version}  # {self.latest_release.url}\n"
                replacement += line

        with open(PACKAGING_PATH.format(self.package), "w") as packaging_file_write:
            packaging_file_write.write(replacement)

    def open_pr_exists(self) -> bool:
        prs_exist = False

        for pr in self.remote_repo.get_pulls(
            state="open", base=PR_BASE, head=f"{PR_ORG}:{self.pr_branch}"
        ):  # theoretically there shold never be more than one open PR, print them anyways
            print(f"Open {self.pr_branch} PR exists: {pr.html_url}")
            prs_exist = True
        return prs_exist

    def create_pr(self):
        print(f"[{self.name}] Creating bump branch {PR_ORG}:{self.pr_branch} and PR...")
        pr_body = textwrap.dedent(
            f"""
            Automatic bump from version {self.current_version} to version {self.latest_release.version}, downloaded from {self.latest_release.url}.

            After merge, consider releasing a new version of haproxy-boshrelease.
        """
        )
        if not DRY_RUN:
            self._create_branch(self.remote_repo, self.pr_branch)

            self._update_file(
                self.remote_repo,
                PACKAGING_PATH.format(self.package),
                self.pr_branch,
                f"Bump {self.name} version to {self.latest_release.version}",
            )
            self._update_file(
                self.remote_repo,
                BLOBS_PATH,
                self.pr_branch,
                f"Update blob reference for {self.name} to version {self.latest_release.version}",
            )

            pr = self.remote_repo.create_pull(
                base=PR_BASE,
                head=f"{PR_ORG}:{self.pr_branch}",
                title=f"Bump {self.name} version to {self.latest_release.version}",
                body=pr_body,
                draft=False,
            )
            pr.add_to_labels(PR_LABEL)
            print(f"[{self.name}] Created Pull Request: {pr.html_url}")


    def _create_branch(self, repo, branch):
        """
        Creates the branch with the given name.
        If it exists, deletes the existing branch and creates a new one.
        """
        try:
            ref = repo.get_git_ref(f"heads/{branch}")
            ref.delete()
        except github.UnknownObjectException:
            print(f"Branch {branch} didn't exist. We'll create it.")
        finally:
            base_branch = repo.get_git_ref(f"heads/{PR_BASE}")
            repo.create_git_ref(f"refs/heads/{branch}", base_branch.object.sha)

    def _update_file(self, repo, path, branch, message):
        with open(path, "rb") as f:
            content = f.read()
            github_file = repo.get_contents(path, ref=branch)
            repo.update_file(path=path, message=message, content=content, sha=github_file.sha, branch=branch)


@dataclass
class GithubDependency(Dependency):

    tagname_prefix: str = ""
    filename_suffix: str = ".tar.gz"

    def fetch_latest_release(self) -> Release:
        repo_org_and_name = self.root_url.lstrip("https://github.com/")
        repo = gh.get_repo(repo_org_and_name)
        releases = repo.get_releases()

        def get_release_download_url(rel):
            assets = rel.get_assets()
            for asset in assets:
                if asset.name.endswith(self.filename_suffix):
                    return asset.browser_download_url
            raise Exception(f"No *{self.filename_suffix} asset found for release '{rel}'")

        latest_release = None
        latest_version = version.parse("0.0.0")

        for rel in releases:
            current_raw = rel.tag_name.lstrip(self.tagname_prefix)
            current_version = version.parse(current_raw)
            if latest_version < current_version and current_raw.startswith(self.pinned_version):
                latest_version = current_version
                latest_release = Release(
                    rel.title,
                    get_release_download_url(rel),
                    f"{self.name}-{str(current_version)}{self.filename_suffix}",
                    current_version,
                )

        if latest_version == version.parse("0.0.0"):
            raise Exception(f"No release found for '{repo}'")

        return latest_release


@dataclass
class WebLinkDependency(Dependency):

    selector: str = "a"
    pattern: str = "({name}-({pinned_version}" + r"(?:\.[0-9])+))\.tar\.gz"

    def fetch_latest_release(self) -> Release:
        data = requests.get(self.root_url)
        html = BeautifulSoup(data.text, "html.parser")

        versions = []
        links = [link for link in html.select(self.selector) if "href" in link.attrs]

        for link in links:
            match = re.search(
                self.pattern.format(name=self.name, pinned_version=self.pinned_version),
                link.attrs["href"],
            )
            if match:
                versions.append(
                    Release(
                        match.group(1),  # full name without extension
                        requests.compat.urljoin(self.root_url, link.attrs["href"]),  # absolute URL based on relative link href
                        match.group(0),  # full file name with extension
                        version.parse(match.group(2)),  # version
                    )
                )

        if versions:
            # sort found versions with highest first, return first entry, i.e. highest applicable version number.
            return sorted(versions, key=lambda r: r.version, reverse=True)[0]

        raise Exception(f"Failed to get latest {self.name} version from {self.root_url}")


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
        return Release(
            latest_release["file"].rstrip(".tar.gz"),
            download_url,
            latest_release["file"],
            version.parse(latest_version),
        )


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
                "credentials_source": "static",
                "json_key": BLOBSTORE_SECRET_ACCESS_KEY,
            }
        }
    }
    with open("config/private.yml", "w") as file:
        yaml.dump(private_yml, file, default_flow_style=False)


def cleanup_local_changes():
    local_git = Repo(os.curdir).git
    local_git.reset("--hard")
    local_git.clean("-fx")


def main() -> None:
    dependencies: List[Dependency] = [
        WebLinkDependency(
            "keepalived",
            "KEEPALIVED_VERSION",
            "2.2",
            "https://keepalived.org/download.html",
            package="keepalived",
            selector="div.content a",
        ),
        WebLinkDependency(
            "socat",
            "SOCAT_VERSION",
            "1.7",
            "http://www.dest-unreach.org/socat/download/",
        ),
        HaproxyDependency(
            "haproxy",
            "HAPROXY_VERSION",
            "2.7",
            "https://www.haproxy.org/download/{}/src",
        ),
        WebLinkDependency(
            "lua",
            "LUA_VERSION",
            "5.4",
            "https://www.lua.org/versions.html",
        ),
        GithubDependency(
            "pcre2",
            "PCRE_VERSION",
            "10",
            "https://github.com/PCRE2Project/pcre2",
            tagname_prefix="pcre2-",
        ),
        GithubDependency(
            "hatop",
            "HATOP_VERSION",
            "0",
            "https://github.com/jhunt/hatop",
            tagname_prefix="v",
            filename_suffix="",
        ),
        # ttar (currently a submodule to https://github.com/jhunt/ttar, no new releases. Manual bump only.)
    ]

    write_private_yaml()

    for dependency in dependencies:
        current_version = dependency.current_version
        latest_release = dependency.latest_release
        latest_version = latest_release.version

        if latest_version <= current_version:
            print(f"[{dependency.name}] already on the latest version: {latest_version} " f"(pinned: {dependency.pinned_version}.*)")
            continue

        if dependency.open_pr_exists():
            print(f"[{dependency.name}] Open bump PR exists (for branch: {dependency.pr_branch})")
            continue
        print(f"[{dependency.name}] Version-Bump required: {current_version} --> {latest_version}")
        latest_release.download()
        dependency.remove_current_blob()
        latest_release.add_blob(dependency.package)
        dependency.update_packaging_file()
        if not DRY_RUN:
            BoshHelper.upload_blobs()
        dependency.create_pr()

        # clear the working directory for the next dependency bump.
        cleanup_local_changes()


if __name__ == "__main__":
    main()
