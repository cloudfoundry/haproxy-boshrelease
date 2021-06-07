package acceptance_tests

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"time"
)

// starts a local http server handling the provided handler
// returns a close function to stop the server and the port the server is listening on
func startLocalHTTPServer(handler func(http.ResponseWriter, *http.Request)) (func(), int, error) {
	server := httptest.NewServer(http.HandlerFunc(handler))
	serverURL, err := url.Parse(server.URL)
	if err != nil {
		return nil, 0, err
	}

	port, err := strconv.ParseInt(serverURL.Port(), 10, 64)
	if err != nil {
		return nil, 0, err
	}

	return server.Close, int(port), nil
}

// Build an HTTP client with custom CAcertificate pool
// which resolves hosts based on provided map
func buildHTTPClient(caCerts []string, addressMap map[string]string, clientCerts []tls.Certificate) *http.Client {
	// Create HTTP Client with custom CAs
	caCertPool := x509.NewCertPool()

	for _, caCert := range caCerts {
		caCertPool.AppendCertsFromPEM([]byte(caCert))
	}

	tlsConfig := &tls.Config{
		RootCAs:      caCertPool,
		Certificates: clientCerts,
	}

	transport := &http.Transport{TLSClientConfig: tlsConfig}

	// Override HTTP transport to force resolve with alternative addresses
	transport.DialContext = func(ctx context.Context, network, addr string) (net.Conn, error) {
		if altAddr, ok := addressMap[addr]; ok {
			addr = altAddr
		}

		return (&net.Dialer{
			Timeout:   30 * time.Second,
			KeepAlive: 30 * time.Second,
		}).DialContext(ctx, network, addr)
	}
	return &http.Client{Transport: transport}
}
