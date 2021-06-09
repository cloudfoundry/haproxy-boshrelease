package acceptance_tests

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"log"
	"net"

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

	return scpClient.CopyFile(fileReader, remotePath, permissions)
}

// Forwards a TCP connection from a given port on the remote machine to a given port on the local machine
// Starts in backgound, cancel via context
func startReverseSSHPortForwarder(user string, addr string, privateKey string, remotePort, localPort int, ctx context.Context) error {
	remoteConn, err := buildSSHClient(user, addr, privateKey)
	if err != nil {
		return err
	}

	fmt.Printf("Listening on 127.0.0.1:%d on remote machine\n", remotePort)
	remoteListener, err := remoteConn.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", remotePort))
	if err != nil {
		return err
	}

	go func() {
		for {
			remoteClient, err := remoteListener.Accept()
			if err != nil {
				fmt.Printf("Error accepting connection on remote listener: %s (may have been closed)\n", err.Error())
				return
			}

			localConn, err := net.Dial("tcp", fmt.Sprintf("127.0.0.1:%d", localPort))
			if err != nil {
				fmt.Printf("Error dialing local port %d: %s\n", localPort, err.Error())
				return
			}

			// From https://sosedoff.com/2015/05/25/ssh-port-forwarding-with-go.html
			copyConnections(remoteClient, localConn)
		}
	}()

	go func() {
		<-ctx.Done()
		fmt.Println("Closing remote listener")
		remoteListener.Close()
	}()

	return nil
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

	fmt.Printf("Connecting to %s:%d as user %s using private key\n", addr, 22, user)
	return ssh.Dial("tcp", net.JoinHostPort(addr, "22"), config)
}
