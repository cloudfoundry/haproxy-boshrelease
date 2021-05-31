package acceptance_tests

import (
	"testing"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

func TestAcceptanceTests(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "AcceptanceTests Suite")
}

var _ = BeforeSuite(func() {
	var err error
	config, err = loadConfig()
	Expect(err).NotTo(HaveOccurred())
})

var _ = AfterSuite(func() {
})
