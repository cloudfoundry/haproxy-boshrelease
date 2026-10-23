"""
Offline tests for ci/scripts/autobump-dependencies.py — specifically the version
RESOLUTION logic (the bug-prone part: tag/version parsing, pinned-version filtering,
prerelease/invalid skipping, asset/filename matching, blob naming).

Runs with no network, no GitHub token, and no bosh: the module is import-safe
(env vars read via .get, remote_repo is lazy), and these tests stub the GitHub
client (autobump.gh) and requests.get. They do NOT touch main()'s side effects
(download / bosh add-blob / git reset / PR creation).

Run:  pytest ci/scripts/test_autobump_dependencies.py
"""
import importlib.util
import pathlib

import pytest
from packaging import version

# Load the dash-named script as a module.
_spec = importlib.util.spec_from_file_location(
    "autobump_dependencies",
    pathlib.Path(__file__).with_name("autobump-dependencies.py"),
)
autobump = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(autobump)


# --- fakes for the PyGithub client -------------------------------------------------
class FakeAsset:
    def __init__(self, name):
        self.name = name
        self.browser_download_url = f"https://example.invalid/{name}"


class FakeRelease:
    def __init__(self, tag_name, prerelease=False, assets=None):
        self.tag_name = tag_name
        self.name = tag_name
        self.prerelease = prerelease
        self._assets = assets or []

    def get_assets(self):
        return self._assets


class FakeTag:
    def __init__(self, name):
        self.name = name


class FakeRepo:
    def __init__(self, releases=None, tags=None):
        self._releases = releases or []
        self._tags = tags or []

    def get_releases(self):
        return self._releases

    def get_tags(self):
        return self._tags


class FakeGithub:
    def __init__(self, repo):
        self._repo = repo

    def get_repo(self, _name):
        return self._repo


class FakeResponse:
    def __init__(self, text, status_code=200):
        self.text = text
        self.status_code = status_code


# --- import is offline-safe --------------------------------------------------------
def test_module_imports_without_env_or_network():
    # Reaching here means exec_module succeeded with no GCP/GITHUB/PR_* env and no API call.
    assert hasattr(autobump, "build_dependencies")
    assert hasattr(autobump, "Dependency")


def test_build_dependencies_is_complete_and_offline():
    names = [d.name for d in autobump.build_dependencies()]
    assert set(names) == {
        "keepalived", "socat", "haproxy", "lua", "pcre2", "hatop",
        "aws-lc", "cmake", "golang",
    }


# --- GithubDependency (releases + assets) ------------------------------------------
def test_github_dependency_picks_highest_pinned_non_prerelease(monkeypatch):
    repo = FakeRepo(releases=[
        FakeRelease("pcre2-10.44", assets=[FakeAsset("pcre2-10.44.tar.gz")]),
        FakeRelease("pcre2-10.45", assets=[FakeAsset("pcre2-10.45.tar.gz")]),
        FakeRelease("pcre2-11.0", assets=[FakeAsset("pcre2-11.0.tar.gz")]),      # wrong pin (10)
        FakeRelease("pcre2-10.46", prerelease=True, assets=[FakeAsset("pcre2-10.46.tar.gz")]),  # prerelease
    ])
    monkeypatch.setattr(autobump, "gh", FakeGithub(repo))

    dep = autobump.GithubDependency(
        name="pcre2", version_var_name="PCRE_VERSION", pinned_version="10",
        root_url="https://github.com/PCRE2Project/pcre2", tagname_prefix="pcre2-",
    )
    rel = dep.fetch_latest_release()
    assert str(rel.version) == "10.45"
    assert rel.file == "pcre2-10.45.tar.gz"
    assert rel.url == "https://example.invalid/pcre2-10.45.tar.gz"


# --- GithubArchiveDependency (tags, skips invalid + prerelease + wrong pin) ---------
def test_github_archive_dependency_tag_resolution(monkeypatch):
    repo = FakeRepo(tags=[
        FakeTag("v4.0.0"),
        FakeTag("v4.0.1"),
        FakeTag("v4.1.0"),
        FakeTag("v5.0.0"),              # wrong pin (4)
        FakeTag("AWS-LC-FIPS-3.3.0"),   # wrong pin / not vX
        FakeTag("v4-foo"),              # starts with 4 but InvalidVersion -> skipped
        FakeTag("v4.2.0-rc1"),          # prerelease -> skipped
    ])
    monkeypatch.setattr(autobump, "gh", FakeGithub(repo))

    dep = autobump.GithubArchiveDependency(
        name="aws-lc", version_var_name="AWS_LC_VERSION", pinned_version="4",
        root_url="https://github.com/aws/aws-lc", tagname_prefix="v", blob_version_prefix="v",
    )
    rel = dep.fetch_latest_release()
    assert str(rel.version) == "4.1.0"
    assert rel.file == "aws-lc-v4.1.0.tar.gz"
    assert rel.url == "https://github.com/aws/aws-lc/archive/refs/tags/v4.1.0.tar.gz"


# --- GolangDependency (go.dev HTML scrape) -----------------------------------------
def test_golang_dependency_scrapes_pinned_minor(monkeypatch):
    html = """
      <a href="/dl/go1.27.0.linux-amd64.tar.gz">go1.27.0</a>
      <a href="/dl/go1.27.1.linux-amd64.tar.gz">go1.27.1</a>
      <a href="/dl/go1.28.0.linux-amd64.tar.gz">go1.28.0</a>
    """
    monkeypatch.setattr(autobump.requests, "get", lambda *_a, **_k: FakeResponse(html))

    dep = autobump.GolangDependency(
        name="golang", version_var_name="GOLANG_VERSION", pinned_version="1.27",
        root_url="https://go.dev/dl/",
    )
    rel = dep.fetch_latest_release()
    assert str(rel.version) == "1.27.1"
    assert rel.file == "golang-1.27.1.tar.gz"


# --- WebLinkDependency (generic download-page scrape) ------------------------------
def test_weblink_dependency_scrape(monkeypatch):
    html = """
      <a href="socat-1.8.0.0.tar.gz">socat-1.8.0.0</a>
      <a href="socat-1.8.0.1.tar.gz">socat-1.8.0.1</a>
    """
    monkeypatch.setattr(autobump.requests, "get", lambda *_a, **_k: FakeResponse(html))

    dep = autobump.WebLinkDependency(
        name="socat", version_var_name="SOCAT_VERSION", pinned_version="1",
        root_url="http://www.dest-unreach.org/socat/download/",
    )
    rel = dep.fetch_latest_release()
    assert str(rel.version) == "1.8.0.1"
    assert rel.file == "socat-1.8.0.1.tar.gz"


# --- HaproxyDependency (releases.json) ---------------------------------------------
def test_haproxy_dependency_reads_releases_json(monkeypatch):
    payload = '{"latest_release": "3.2.26", "releases": {"3.2.26": {"file": "haproxy-3.2.26.tar.gz"}}}'
    monkeypatch.setattr(autobump.requests, "get", lambda *_a, **_k: FakeResponse(payload))

    dep = autobump.HaproxyDependency(
        name="haproxy", version_var_name="HAPROXY_VERSION", pinned_version="3.2",
        root_url="https://www.haproxy.org/download/{}/src",
    )
    rel = dep.fetch_latest_release()
    assert str(rel.version) == "3.2.26"
    assert rel.file == "haproxy-3.2.26.tar.gz"
    assert rel.url.endswith("/download/3.2/src/haproxy-3.2.26.tar.gz")


# --- current_version parsing (from the versions file) ------------------------------
def test_current_version_parsed_from_versions_file(tmp_path):
    vfile = tmp_path / "versions.sh"
    vfile.write_text("FOO_VERSION=1.2.3  # https://example.invalid/foo-1.2.3.tar.gz\n")
    dep = autobump.GithubDependency(
        name="foo", version_var_name="FOO_VERSION", pinned_version="1",
        root_url="https://github.com/o/r", versions_path=str(vfile),
    )
    assert dep.current_version == version.parse("1.2.3")


# --- no-bump decision uses >= on parsed versions (sanity on the comparison) --------
def test_version_comparison_semantics():
    assert version.parse("3.2.26") > version.parse("3.2.9")   # not lexical
    assert version.parse("10.45") > version.parse("10.9")


# --- main() side-effect gating by DRY_RUN ------------------------------------------
class _FakeDep:
    """A dependency that is 'behind', so main() would try to bump it."""
    name = "cmake"
    pinned_version = "4"
    package = "haproxy"
    pr_branch = "cmake-auto-bump-master"

    def __init__(self, latest):
        self._latest = latest
        self.calls = []

    @property
    def current_version(self):
        return version.parse("4.4.3")

    @property
    def latest_release(self):
        return self._latest

    def open_pr_exists(self):
        self.calls.append("open_pr_exists")
        return False

    def remove_current_blob(self):
        self.calls.append("remove_current_blob")

    def update_packaging_file(self):
        self.calls.append("update_packaging_file")

    def create_pr(self):
        self.calls.append("create_pr")


def _wire_main(monkeypatch, dry_run):
    """Stub every side-effecting hook so main() can run offline; return the call log + dep."""
    module_calls = []
    monkeypatch.setattr(autobump, "DRY_RUN", dry_run)
    monkeypatch.setattr(autobump, "_require_env", lambda: None)
    monkeypatch.setattr(autobump, "write_private_yaml", lambda: module_calls.append("write_private_yaml"))
    monkeypatch.setattr(autobump, "wget", lambda *a, **k: module_calls.append("wget"))
    monkeypatch.setattr(autobump, "cleanup_local_changes", lambda: module_calls.append("cleanup"))
    monkeypatch.setattr(autobump.BoshHelper, "add_blob", classmethod(lambda cls, *a: module_calls.append("add_blob")))
    monkeypatch.setattr(autobump.BoshHelper, "remove_blob", classmethod(lambda cls, *a: module_calls.append("remove_blob")))
    monkeypatch.setattr(autobump.BoshHelper, "upload_blobs", classmethod(lambda cls: module_calls.append("upload_blobs")))
    rel = autobump.Release("cmake-4.4.4", "https://example.invalid/cmake-4.4.4.tar.gz", "cmake-4.4.4.tar.gz", version.parse("4.4.4"))
    dep = _FakeDep(rel)
    monkeypatch.setattr(autobump, "build_dependencies", lambda: [dep])
    return module_calls, dep


def test_dry_run_is_side_effect_free(monkeypatch):
    module_calls, dep = _wire_main(monkeypatch, dry_run=True)
    autobump.main()
    # A behind dependency is reported but NOTHING is touched.
    assert module_calls == []
    assert dep.calls == []


def test_real_run_performs_the_bump(monkeypatch):
    module_calls, dep = _wire_main(monkeypatch, dry_run=False)
    autobump.main()
    # The full bump pipeline runs, including the destructive cleanup.
    assert "write_private_yaml" in module_calls
    assert "wget" in module_calls          # Release.download
    assert "add_blob" in module_calls      # Release.add_blob -> BoshHelper
    assert "upload_blobs" in module_calls
    assert "cleanup" in module_calls
    assert dep.calls == ["open_pr_exists", "remove_current_blob", "update_packaging_file", "create_pr"]
