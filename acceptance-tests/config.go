package acceptance_tests

import (
	"fmt"
	"os"
	"os/exec"
)

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
}

var config Config

func loadConfig() (Config, error) {
	releaseRepoPath, err := getEnvOrFail("REPO_ROOT")
	if err != nil {
		return Config{}, nil
	}

	releaseVersion, err := getEnvOrFail("RELEASE_VERSION")
	if err != nil {
		return Config{}, nil
	}

	boshCACert, err := getEnvOrFail("BOSH_CA_CERT")
	if err != nil {
		return Config{}, nil
	}

	boshClient, err := getEnvOrFail("BOSH_CLIENT")
	if err != nil {
		return Config{}, nil
	}

	boshClientSecret, err := getEnvOrFail("BOSH_CLIENT_SECRET")
	if err != nil {
		return Config{}, nil
	}

	boshEnvironment, err := getEnvOrFail("BOSH_ENVIRONMENT")
	if err != nil {
		return Config{}, nil
	}

	boshPath, err := getEnvOrFail("BOSH_PATH")
	if err != nil {
		return Config{}, nil
	}

	baseManifestPath, err := getEnvOrFail("BASE_MANIFEST_PATH")
	if err != nil {
		return Config{}, nil
	}

	// BOSH commands require HOME is set
	homePath, err := getEnvOrFail("HOME")
	if err != nil {
		return Config{}, nil
	}

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
	}, nil
}

func (config *Config) boshCmd(boshDeployment string, args ...string) *exec.Cmd {
	cmd := exec.Command(config.BoshPath, args...)
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
