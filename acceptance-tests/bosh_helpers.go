package acceptance_tests

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"os/exec"
	"strings"
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gexec"
	"gopkg.in/yaml.v2"
)

type haproxyInfo struct {
	SSHPrivateKey           string
	SSHPublicKey            string
	SSHPublicKeyFingerprint string
	SSHUser                 string
	PublicIP                string
}

type baseManifestVars struct {
	haproxyBackendPort    int
	haproxyBackendServers []string
	deploymentName        string
}

type varsStoreReader func(interface{}) error

var opsfileChangeName string = `---
# change deployment name to allow multiple simulataneous deployments
- type: replace
  path: /name
  value: ((deployment-name))
`

var opsfileChangeVersion string = `---
# Deploy dev version we just compiled
- type: replace
  path: /releases/name=haproxy
  value:
    name: haproxy
    version: ((release-version))
`

var opsfileAddSSHUser string = `---
# Install OS conf so that we can SSH into VM to inspect configuration
- type: replace
  path: /releases/-
  value:
    name: os-conf
    version: "22.1.1"
    url: https://bosh.io/d/github.com/cloudfoundry/os-conf-release?v=22.1.1
    sha1: "4f653168954749992a541d228dd4f936f2eff2d6"

# Add an SSH user
- type: replace
  path: /instance_groups/name=haproxy/jobs/-
  value:
    name: user_add
    release: os-conf
    properties:
      users:
      - name: ((ssh_user))
        public_key: ((ssh_key.public_key))
        sudo: true

# Generate an SSH key-pair
- type: replace
  path: /variables?/-
  value:
    name: ssh_key
    type: ssh
`

// opsfiles that need to be set for all tests
var defaultOpsfiles = []string{opsfileChangeName, opsfileChangeVersion, opsfileAddSSHUser}
var defaultSSHUser string = "ginkgo"

func buildManifestVars(baseManifestVars baseManifestVars, customVars map[string]interface{}) map[string]interface{} {
	vars := map[string]interface{}{
		"release-version":         config.ReleaseVersion,
		"haproxy-backend-port":    fmt.Sprintf("%d", baseManifestVars.haproxyBackendPort),
		"haproxy-backend-servers": baseManifestVars.haproxyBackendServers,
		"deployment-name":         baseManifestVars.deploymentName,
		"ssh_user":                defaultSSHUser,
	}
	for k, v := range customVars {
		vars[k] = v
	}

	return vars
}

func buildHAProxyInfo(baseManifestVars baseManifestVars, varsStoreReader varsStoreReader) haproxyInfo {
	var creds struct {
		SSHKey struct {
			PrivateKey           string `yaml:"private_key"`
			PublicKey            string `yaml:"public_key"`
			PublicKeyFingerprint string `yaml:"public_key_fingerprint"`
		} `yaml:"ssh_key"`
	}
	err := varsStoreReader(&creds)
	Expect(err).NotTo(HaveOccurred())

	Expect(creds.SSHKey.PrivateKey).NotTo(BeEmpty())
	Expect(creds.SSHKey.PublicKey).NotTo(BeEmpty())

	By("Fetching the HAProxy public IP")
	instances := boshInstances(baseManifestVars.deploymentName)
	haproxyPublicIP := instances[0].ParseIPs()[0]
	Expect(haproxyPublicIP).ToNot(BeEmpty())

	return haproxyInfo{
		PublicIP:                haproxyPublicIP,
		SSHPrivateKey:           creds.SSHKey.PrivateKey,
		SSHPublicKey:            creds.SSHKey.PublicKey,
		SSHPublicKeyFingerprint: creds.SSHKey.PublicKeyFingerprint,
		SSHUser:                 defaultSSHUser,
	}
}

// Helper method for deploying HAProxy
// Takes the HAProxy base manifest vars, an array of custom opsfiles, and a map of custom vars
// Returns 'info' struct containing public IP and ssh creds, and a callback to deserialise properties from the vars store
func deployHAProxy(baseManifestVars baseManifestVars, customOpsfiles []string, customVars map[string]interface{}, expectSuccess bool) (haproxyInfo, varsStoreReader) {
	manifestVars := buildManifestVars(baseManifestVars, customVars)
	opsfiles := append(defaultOpsfiles, customOpsfiles...)
	cmd, varsStoreReader := deployBaseManifestCmd(baseManifestVars.deploymentName, opsfiles, manifestVars)

	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())

	if expectSuccess {
		Eventually(session, 10*time.Minute, time.Second).Should(gexec.Exit(0))
	} else {
		Eventually(session, 10*time.Minute, time.Second).Should(gexec.Exit())
		Expect(session.ExitCode()).NotTo(BeZero())
	}

	haproxyInfo := buildHAProxyInfo(baseManifestVars, varsStoreReader)

	// Dump HAProxy config to help debugging
	dumpHAProxyConfig(haproxyInfo)

	return haproxyInfo, varsStoreReader
}

func dumpHAProxyConfig(haproxyInfo haproxyInfo) {
	By("Checking /var/vcap/jobs/haproxy/config/haproxy.config")
	haProxyConfig, _, err := runOnRemote(haproxyInfo.SSHUser, haproxyInfo.PublicIP, haproxyInfo.SSHPrivateKey, "cat /var/vcap/jobs/haproxy/config/haproxy.config")
	Expect(err).NotTo(HaveOccurred())
	fmt.Println("HAProxy Config")

	fmt.Println("---------- HAProxy Config ----------")
	fmt.Println(haProxyConfig)
	fmt.Println("------------------------------------")
}

// Takes bosh deployment name, ops files and vars.
// Returns a cmd object and a callback to deserialise the bosh-generated vars store after cmd has executed
func deployBaseManifestCmd(boshDeployment string, opsFilesContents []string, vars map[string]interface{}) (*exec.Cmd, varsStoreReader) {
	By(fmt.Sprintf("Deploying HAProxy (deployment name: %s)", boshDeployment))
	args := []string{"deploy"}

	// ops files
	for _, opsFileContents := range opsFilesContents {
		opsFile, err := ioutil.TempFile("", "haproxy-tests-ops-file-*.yml")
		Expect(err).NotTo(HaveOccurred())

		fmt.Printf("Writing ops file to %s\n", opsFile.Name())
		fmt.Println("------------------------------------")
		fmt.Println(opsFileContents)
		fmt.Println("------------------------------------")

		_, err = opsFile.WriteString(opsFileContents)
		Expect(err).NotTo(HaveOccurred())
		err = opsFile.Close()
		Expect(err).NotTo(HaveOccurred())

		args = append(args, "--ops-file", opsFile.Name())
	}

	// vars file
	if vars != nil {
		varsFile, err := ioutil.TempFile("", "haproxy-tests-vars-file-*.json")
		Expect(err).NotTo(HaveOccurred())

		bytes, err := json.Marshal(vars)
		Expect(err).NotTo(HaveOccurred())

		fmt.Printf("Writing vars file to %s\n", varsFile.Name())
		fmt.Println("------------------------------------")
		fmt.Println(string(bytes))
		fmt.Println("------------------------------------")

		_, err = varsFile.Write(bytes)
		Expect(err).NotTo(HaveOccurred())
		err = varsFile.Close()
		Expect(err).NotTo(HaveOccurred())

		args = append(args, "--vars-file", varsFile.Name())
	}

	// vars store
	varsStore, err := ioutil.TempFile("", "haproxy-tests-vars-store-*.yml")
	Expect(err).NotTo(HaveOccurred())

	_, err = varsStore.WriteString("{}")
	Expect(err).NotTo(HaveOccurred())
	err = varsStore.Close()
	Expect(err).NotTo(HaveOccurred())

	args = append(args, "--vars-store", varsStore.Name())
	args = append(args, config.BaseManifestPath)

	varsStoreReader := func(target interface{}) error {
		varsStoreBytes, err := ioutil.ReadFile(varsStore.Name())
		if err != nil {
			return err
		}

		return yaml.Unmarshal(varsStoreBytes, target)
	}

	return config.boshCmd(boshDeployment, args...), varsStoreReader
}

type boshInstance struct {
	AgentID           string `json:"agent_id"`
	Az                string `json:"az"`
	Bootstrap         string `json:"bootstrap"`
	Deployment        string `json:"deployment"`
	DiskCids          string `json:"disk_cids"`
	Ignore            string `json:"ignore"`
	Index             string `json:"index"`
	Instance          string `json:"instance"`
	CommaSeparatedIPs string `json:"ips"`
	ProcessState      string `json:"process_state"`
	State             string `json:"state"`
	VMCid             string `json:"vm_cid"`
	VMType            string `json:"vm_type"`
}

func (instance boshInstance) ParseIPs() []string {
	return strings.Split(instance.CommaSeparatedIPs, ",")
}

func boshInstances(boshDeployment string) []boshInstance {
	fmt.Printf("Fetching Bosh instances")
	cmd := config.boshCmd(boshDeployment, "--json", "instances", "--details")
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	Eventually(session, time.Minute, time.Second).Should(gexec.Exit(0))

	output := struct {
		Tables []struct {
			Rows []boshInstance `json:"Rows"`
		} `json:"Tables"`
	}{}

	err = json.Unmarshal(session.Out.Contents(), &output)
	Expect(err).NotTo(HaveOccurred())

	return output.Tables[0].Rows
}

func deleteDeployment(boshDeployment string) {
	By(fmt.Sprintf("Deleting HAProxy deployment (deployment name: %s)", boshDeployment))
	cmd := config.boshCmd(boshDeployment, "delete-deployment")
	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())
	Eventually(session, 10*time.Minute, time.Second).Should(gexec.Exit(0))
}

func waitForHAProxyListening(haproxyInfo haproxyInfo) {
	Eventually(func() error {
		return checkListening(fmt.Sprintf("%s:443", haproxyInfo.PublicIP))
	}, 2*time.Minute, 5*time.Second).ShouldNot(HaveOccurred())
}

func reloadHAProxy(haproxyInfo haproxyInfo) {
	_, _, err := runOnRemote(haproxyInfo.SSHUser, haproxyInfo.PublicIP, haproxyInfo.SSHPrivateKey, "sudo /var/vcap/jobs/haproxy/bin/reload")
	Expect(err).NotTo(HaveOccurred())
	time.Sleep(10 * time.Second)
}
