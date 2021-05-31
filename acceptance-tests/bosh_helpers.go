package acceptance_tests

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"strings"
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gexec"
	"gopkg.in/yaml.v2"
)

type haproxyInfo struct {
	SSHPrivateKey string
	SSHUser       string
	PublicIP      string
}

type varsStoreReader func(interface{}) error

// Helper method for deploying HAProxy
// Takes the HAProxy backend port, an array of custom opsfiles, a map of custom vars
// Returns 'info' struct containing public IP and ssh creds, and a callback to deserialise properties from the vars store
func deployHAProxy(haproxyBackendPort int, customOpsfiles []string, customVars map[string]interface{}) (haproxyInfo, varsStoreReader) {
	sshUser := "ginkgo"

	opsfileChangeVersion := `---
# Deploy dev version we just compiled
- type: replace
  path: /releases/name=haproxy
  value:
    name: haproxy
    version: ((release-version))
`

	opsfileAddSSHUser := `---
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

	vars := map[string]interface{}{
		"release-version":         config.ReleaseVersion,
		"haproxy-backend-port":    fmt.Sprintf("%d", haproxyBackendPort),
		"haproxy-backend-servers": []string{"127.0.0.1"},
		"ssh_user":                sshUser,
	}
	for k, v := range customVars {
		vars[k] = v
	}

	opsfiles := append([]string{opsfileChangeVersion, opsfileAddSSHUser}, customOpsfiles...)
	session, varsStoreReader := deployBaseManifest(opsfiles, vars)
	Eventually(session, 10*time.Minute, time.Second).Should(gexec.Exit(0))

	var creds struct {
		SSHKey struct {
			PrivateKey string `yaml:"private_key"`
			PublicKey  string `yaml:"public_key"`
		} `yaml:"ssh_key"`
	}
	err := varsStoreReader(&creds)
	Expect(err).NotTo(HaveOccurred())

	Expect(creds.SSHKey.PrivateKey).NotTo(BeEmpty())
	Expect(creds.SSHKey.PublicKey).NotTo(BeEmpty())

	By("Fetching the HAProxy public IP")
	instances := boshInstances()
	haproxyPublicIP := instances[0].ParseIPs()[0]
	Expect(haproxyPublicIP).ToNot(BeEmpty())

	return haproxyInfo{
		PublicIP:      haproxyPublicIP,
		SSHPrivateKey: creds.SSHKey.PrivateKey,
		SSHUser:       sshUser,
	}, varsStoreReader
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

// Takes bosh deploy ops files and vars.
// Returns a session object and a callback to deserialise the bosh-generated vars store after session has executed
func deployBaseManifest(opsFilesContents []string, vars map[string]interface{}) (*gexec.Session, varsStoreReader) {
	By("Deploying HAProxy")
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

	cmd := config.boshCmd(args...)

	session, err := gexec.Start(cmd, GinkgoWriter, GinkgoWriter)
	Expect(err).NotTo(HaveOccurred())

	return session, varsStoreReader
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

func boshInstances() []boshInstance {
	fmt.Printf("Fetching Bosh instances")
	cmd := config.boshCmd("--json", "instances", "--details")
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

func deleteDeployment() {
	By("Deleting the HAProxy deployment")
	cmd := config.boshCmd("delete-deployment")
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
