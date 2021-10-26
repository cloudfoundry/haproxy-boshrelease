package acceptance_tests

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strconv"
	"strings"
	"time"

	"golang.org/x/net/http2"
)

// starts a local http server handling the provided handler
// returns a close function to stop the server and the port the server is listening on
func startLocalHTTPServer(tlsConfig *tls.Config, handler func(http.ResponseWriter, *http.Request)) (func(), int, error) {
	server := httptest.NewUnstartedServer(http.HandlerFunc(handler))
	if tlsConfig != nil {
		server.TLS = tlsConfig
		server.StartTLS()
	} else {
		server.Start()
	}

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
	tlsConfig := buildTLSConfig(caCerts, clientCerts, serverName)
	transport := &http.Transport{
		TLSClientConfig: tlsConfig,
		// Override DialContext to force resolve with alternative addresses
		DialContext: func(ctx context.Context, network, addr string) (net.Conn, error) {
			if altAddr, ok := addressMap[strings.ToLower(addr)]; ok {
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

func buildTLSConfig(caCerts []string, clientCerts []tls.Certificate, serverName string) *tls.Config {
	caCertPool := x509.NewCertPool()
	for _, caCert := range caCerts {
		caCertPool.AppendCertsFromPEM([]byte(caCert))
	}

	tlsConfig := &tls.Config{
		RootCAs:      caCertPool,
		Certificates: clientCerts,
	}

	if serverName != "" {
		tlsConfig.ServerName = serverName
		tlsConfig.InsecureSkipVerify = true
	}

	return tlsConfig
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

func connectTLSALPNNegotiatedProtocol(protos []string, publicIP string, ca string, sni string) (string, error) {
	config := buildTLSConfig([]string{ca}, []tls.Certificate{}, sni)
	config.NextProtos = protos
	conn, err := tls.Dial("tcp", fmt.Sprintf("%s:443", publicIP), config)
	if err != nil {
		return "", err
	}
	defer conn.Close()

	return conn.ConnectionState().NegotiatedProtocol, nil
}
