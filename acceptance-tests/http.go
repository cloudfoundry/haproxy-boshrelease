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

	"golang.org/x/net/http2"
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

// Build an HTTP client with custom CA certificate pool which resolves hosts based on provided map
func buildHTTPClient(caCerts []string, addressMap map[string]string, clientCerts []tls.Certificate, serverName string) *http.Client {
	caCertPool := x509.NewCertPool()
	for _, caCert := range caCerts {
		caCertPool.AppendCertsFromPEM([]byte(caCert))
	}

	tlsConfig := tls.Config{
		RootCAs:      caCertPool,
		Certificates: clientCerts,
	}

	if serverName != "" {
		tlsConfig.ServerName = serverName
		tlsConfig.InsecureSkipVerify = true
	}

	transport := &http.Transport{
		TLSClientConfig: &tlsConfig,
		// Override DialContext to force resolve with alternative addresses
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			if altAddr, ok := addressMap[addr]; ok {
				addr = altAddr
			}

			return (&net.Dialer{
				Timeout:   30 * time.Second,
				KeepAlive: 30 * time.Second,
			}).DialContext(ctx, network, addr)
		},
	}

	return &http.Client{Transport: transport}
}

// Build an HTTP2 client with custom CA certificate pool which resolves hosts based on provided map
func buildHTTP2Client(caCerts []string, addressMap map[string]string, clientCerts []tls.Certificate) *http.Client {

	httpClient := buildHTTPClient(caCerts, addressMap, clientCerts, "")
	transport := httpClient.Transport.(*http.Transport)
	http2.ConfigureTransport(transport)

	// force HTTP2-only
	transport.TLSClientConfig.NextProtos = []string{"h2"}

	return &http.Client{Transport: transport}
}
