package acceptance_tests

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
)

var config Config

type Config struct {
	ReleaseRepoPath  string `json:"releaseRepoPath"`
	ReleaseVersion   string `json:"releaseVersion"`
	BoshCACert       string `json:"boshCACert"`
	BoshClient       string `json:"boshClient"`
	BoshClientSecret string `json:"boshClientSecret"`
	BoshEnvironment  string `json:"boshEnvironment"`
	BoshPath         string `json:"boshPath"`
	BaseManifestPath string `json:"baseManifestPath"`
	HomePath         string `json:"homePath"`
	Variant          string `json:"variant"`
	IncludePatches   bool   `json:"includePatches"`
}

func loadConfig() (Config, error) {
	releaseRepoPath, err := getEnvOrFail("REPO_ROOT")
	if err != nil {
		return Config{}, err
	}

	releaseVersion, err := getEnvOrFail("RELEASE_VERSION")
	if err != nil {
		return Config{}, err
	}

	boshCACert, err := getEnvOrFail("BOSH_CA_CERT")
	if err != nil {
		return Config{}, err
	}

	boshClient, err := getEnvOrFail("BOSH_CLIENT")
	if err != nil {
		return Config{}, err
	}

	boshClientSecret, err := getEnvOrFail("BOSH_CLIENT_SECRET")
	if err != nil {
		return Config{}, err
	}

	boshEnvironment, err := getEnvOrFail("BOSH_ENVIRONMENT")
	if err != nil {
		return Config{}, err
	}

	boshPath, err := getEnvOrFail("BOSH_PATH")
	if err != nil {
		return Config{}, err
	}

	baseManifestPath, err := getEnvOrFail("BASE_MANIFEST_PATH")
	if err != nil {
		return Config{}, err
	}

	// BOSH commands require HOME is set
	homePath, err := getEnvOrFail("HOME")
	if err != nil {
		return Config{}, err
	}

	// VARIANT selects the SSL library (openssl|awslc|awslc-fips); empty means openssl.
	variant := os.Getenv("VARIANT")
	if variant == "" {
		variant = "openssl"
	}

	// INCLUDE_HAPROXY_PATCHES toggles the patched build (orthogonal to VARIANT).
	includePatches, _ := strconv.ParseBool(os.Getenv("INCLUDE_HAPROXY_PATCHES"))

	return Config{
		ReleaseRepoPath:  releaseRepoPath,
		ReleaseVersion:   releaseVersion,
		BoshCACert:       boshCACert,
		BoshClient:       boshClient,
		BoshClientSecret: boshClientSecret,
		BoshEnvironment:  boshEnvironment,
		BoshPath:         boshPath,
		BaseManifestPath: baseManifestPath,
		HomePath:         homePath,
		Variant:          variant,
		IncludePatches:   includePatches,
	}, nil
}

func (config *Config) boshCmd(boshDeployment string, args ...string) *exec.Cmd {
	cmd := exec.Command(config.BoshPath, append([]string{"--tty", "--no-color"}, args...)...)
	cmd.Env = []string{
		fmt.Sprintf("BOSH_CA_CERT=%s", config.BoshCACert),
		fmt.Sprintf("BOSH_CLIENT=%s", config.BoshClient),
		fmt.Sprintf("BOSH_CLIENT_SECRET=%s", config.BoshClientSecret),
		fmt.Sprintf("BOSH_ENVIRONMENT=%s", config.BoshEnvironment),
		fmt.Sprintf("HOME=%s", config.HomePath),
		fmt.Sprintf("BOSH_DEPLOYMENT=%s", boshDeployment),
		"BOSH_NON_INTERACTIVE=true",
	}

	return cmd
}

func getEnvOrFail(key string) (string, error) {
	value := os.Getenv(key)
	if value == "" {
		return "", fmt.Errorf("required env var %s not found", key)
	}

	return value, nil
}
