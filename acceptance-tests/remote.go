package acceptance_tests

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log"
	"net"
	"time"

	scp "github.com/bramvdbogaerde/go-scp"
	"golang.org/x/crypto/ssh"
)

// runs command on remote machine
func runOnRemote(user string, addr string, privateKey string, cmd string) (string, string, error) {
	client, err := buildSSHClient(user, addr, privateKey)
	if err != nil {
		return "", "", err
	}

	session, err := client.NewSession()
	if err != nil {
		return "", "", err
	}
	defer session.Close()

	var stdOutBuffer bytes.Buffer
	var stdErrBuffer bytes.Buffer
	session.Stdout = &stdOutBuffer
	session.Stderr = &stdErrBuffer
	err = session.Run(cmd)
	return stdOutBuffer.String(), stdErrBuffer.String(), err
}

func copyFileToRemote(user string, addr string, privateKey string, remotePath string, fileReader io.Reader, permissions string) error {
	clientConfig, err := buildSSHClientConfig(user, addr, privateKey)
	if err != nil {
		return err
	}

	scpClient := scp.NewClient(fmt.Sprintf("%s:22", addr), clientConfig)
	if err := scpClient.Connect(); err != nil {
		return err
	}

	return scpClient.CopyFile(context.Background(), fileReader, remotePath, permissions)
}

// Opens a local port forwarding SSH connection. Equivalent to
// ssh -i <privateKey> -L <localIP>:<localPort>:<remoteIP>:<remotePort> <user>@<addr>
func startSSHPortAndIPForwarder(user string, addr string, privateKey string, localIP string, localPort int, remoteIP string, remotePort int, ctx context.Context) error {
	remoteConn, err := buildSSHClient(user, addr, privateKey)
	if err != nil {
		return err
	}

	writeLog(fmt.Sprintf("Listening on %s:%d on local machine\n", localIP, localPort))
	localListener, err := net.Listen("tcp", fmt.Sprintf("%s:%d", localIP, localPort))
	if err != nil {
		return err
	}

	go func() {
		for {
			localClient, err := localListener.Accept()
			if err != nil {
				if err == io.EOF {
					writeLog("Local connection closed")
				} else {
					writeLog(fmt.Sprintf("Error accepting connection on local listener: %s\n", err.Error()))
				}

				return
			}

			remoteConn, err := remoteConn.Dial("tcp", fmt.Sprintf("%s:%d", remoteIP, remotePort))
			if err != nil {
				writeLog(fmt.Sprintf("Error dialing remote ip %s port %d: %s\n", remoteIP, remotePort, err.Error()))
				return
			}

			// From https://sosedoff.com/2015/05/25/ssh-port-forwarding-with-go.html
			copyConnections(localClient, remoteConn)
		}
	}()

	go func() {
		<-ctx.Done()
		writeLog("Closing local listener")
		localListener.Close()
	}()

	return nil
}

// Forwards a TCP connection from a given port on the local machine to a given port on the remote machine
// Starts in background, cancel via context
func startSSHPortForwarder(user string, addr string, privateKey string, localPort, remotePort int, ctx context.Context) error {
	return startSSHPortAndIPForwarder(user, addr, privateKey, "127.0.0.1", localPort, "127.0.0.1", remotePort, ctx)
}

// Opens a remote port forwarding SSH connection. Equivalent to
// ssh -i <privateKey> -R <remoteIP>:<remotePort>:<localIP>:<localPort> <user>@<addr>
func startReverseSSHPortAndIPForwarder(user string, addr string, privateKey string, remoteIP string, remotePort int, localIP string, localPort int, ctx context.Context) error {
	remoteConn, err := buildSSHClient(user, addr, privateKey)
	if err != nil {
		return err
	}

	writeLog(fmt.Sprintf("Listening on %s:%d on remote machine %s\n", remoteIP, remotePort, addr))
	remoteListener, err := remoteConn.Listen("tcp", fmt.Sprintf("%s:%d", remoteIP, remotePort))
	if err != nil {
		return err
	}

	go func() {
		for {
			remoteClient, err := remoteListener.Accept()
			if err != nil {
				if err == io.EOF {
					writeLog("Remote connection closed")
				} else {
					writeLog(fmt.Sprintf("Error accepting connection on remote listener: %s\n", err.Error()))
				}

				return
			}

			localConn, err := net.Dial("tcp", fmt.Sprintf("%s:%d", localIP, localPort))
			if err != nil {
				writeLog(fmt.Sprintf("Error dialing local ip %s port %d: %s\n", localIP, localPort, err.Error()))
				return
			}

			// From https://sosedoff.com/2015/05/25/ssh-port-forwarding-with-go.html
			copyConnections(remoteClient, localConn)
		}
	}()

	go func() {
		<-ctx.Done()
		writeLog("Closing remote listener")
		remoteListener.Close()
	}()

	return nil
}

// Forwards a TCP connection from a given port on the remote machine to a given port on the local machine
// Starts in background, cancel via context
func startReverseSSHPortForwarder(user string, addr string, privateKey string, remotePort, localPort int, ctx context.Context) error {
	return startReverseSSHPortAndIPForwarder(user, addr, privateKey, "127.0.0.1", remotePort, "127.0.0.1", localPort, ctx)
}

func copyConnections(client net.Conn, remote net.Conn) {
	chDone := make(chan bool)

	// Start remote -> local data transfer
	go func() {
		_, err := io.Copy(client, remote) // blocks until EOF
		if err != nil {
			log.Println("error while copy remote->local:", err)
		}
		chDone <- true
	}()

	// Start local -> remote data transfer
	go func() {
		_, err := io.Copy(remote, client) // blocks until EOF
		if err != nil {
			log.Println("error while copy local->remote:", err)
		}
		chDone <- true
	}()

	<-chDone
}

func buildSSHClientConfig(user string, addr string, privateKey string) (*ssh.ClientConfig, error) {
	key, err := ssh.ParsePrivateKey([]byte(privateKey))
	if err != nil {
		return nil, err
	}

	return &ssh.ClientConfig{
		User:            user,
		Timeout:         10 * time.Second,
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Auth: []ssh.AuthMethod{
			ssh.PublicKeys(key),
		},
	}, nil
}

func buildSSHClient(user string, addr string, privateKey string) (*ssh.Client, error) {
	config, err := buildSSHClientConfig(user, addr, privateKey)
	if err != nil {
		return nil, err
	}

	writeLog(fmt.Sprintf("Connecting to %s:%d as user %s using private key\n", addr, 22, user))
	return ssh.Dial("tcp", net.JoinHostPort(addr, "22"), config)
}

func checkListening(addr string) error {
	conn, err := net.DialTimeout("tcp", addr, time.Second)
	if err != nil {
		return err
	}
	if conn != nil {
		defer conn.Close()
	}

	return nil
}
