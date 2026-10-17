package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"openremote/internal/i18n"
	"openremote/internal/pad"
	"openremote/internal/server"
	"openremote/internal/uinput"
)

func main() {
	addr := flag.String("addr", "0.0.0.0:1337", i18n.T("address for the app", "адрес для приложения"))
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, i18n.T("Usage: openremote [-addr 0.0.0.0:1337]\n\n", "Использование: openremote [-addr 0.0.0.0:1337]\n\n"))
		flag.PrintDefaults()
	}
	flag.Parse()

	dev, err := uinput.Create()
	if err != nil {
		log.Fatal(explain(err))
	}
	defer dev.Close()

	app := server.New(pad.New(dev))
	httpServer := &http.Server{
		Handler:           app.Handler,
		ReadHeaderTimeout: 5 * time.Second,
	}

	ln, err := net.Listen("tcp4", *addr)
	if err != nil {
		if errors.Is(err, syscall.EADDRINUSE) {
			log.Fatalf(i18n.T("port in use: %s", "порт занят: %s"), *addr)
		}
		log.Fatal(err)
	}
	// Small pad frames must leave immediately. Nagle batches a tap's
	// press and release into one packet, and the game never sees the press.
	tcpLn := ln.(*net.TCPListener)

	udpAddr, err := net.ResolveUDPAddr("udp4", *addr)
	if err != nil {
		log.Fatal(err)
	}
	udpConn, err := net.ListenUDP("udp4", udpAddr)
	if err != nil {
		log.Fatal(err)
	}
	defer udpConn.Close()
	go app.ServeUDP(udpConn)

	go func() {
		if err := httpServer.Serve(noDelayListener{tcpLn}); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatal(err)
		}
	}()

	printBanner(*addr, dev)
	log.SetFlags(log.Ltime)

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	<-sig
	fmt.Println(i18n.T("\nstopping", "\nостановка"))

	app.CloseClients()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	_ = httpServer.Shutdown(ctx)
}

type noDelayListener struct{ *net.TCPListener }

func (l noDelayListener) Accept() (net.Conn, error) {
	conn, err := l.AcceptTCP()
	if err != nil {
		return nil, err
	}
	_ = conn.SetNoDelay(true)
	return conn, nil
}

func printBanner(addr string, dev *uinput.Device) {
	_, port, err := net.SplitHostPort(addr)
	if err != nil {
		port = "1337"
	}
	fmt.Println("OpenRemote")
	fmt.Println(i18n.T("virtual Xbox 360", "виртуальный Xbox 360"))
	fmt.Println()
	ips := lanIPv4()
	if len(ips) == 0 {
		ips = []string{"127.0.0.1"}
	}
	fmt.Println(i18n.T("Scan this code in the OpenRemote app:", "Отсканируйте код в приложении OpenRemote:"))
	for _, ip := range ips {
		fmt.Println()
		fmt.Printf("%s:%s\n", ip, port)
		printQR("openremote://" + ip + ":" + port)
	}
	fmt.Println()
	line := i18n.T("Device: Microsoft X-Box 360 pad", "Устройство: Microsoft X-Box 360 pad")
	if dev.EventPath != "" {
		line += "  " + dev.EventPath
	}
	if dev.JSPath != "" {
		line += "  " + dev.JSPath
	}
	fmt.Println(line)
	fmt.Println(i18n.T("Listening on", "Слушает"), addr)
	fmt.Println()
}

func explain(err error) string {
	switch {
	case errors.Is(err, uinput.ErrDeviceNode):
		return i18n.T("no /dev/uinput: run sudo modprobe uinput", "нет /dev/uinput: выполните sudo modprobe uinput")
	case errors.Is(err, uinput.ErrPermission):
		return i18n.T("no access to /dev/uinput: run sudo ./openremote", "нет доступа к /dev/uinput: запустите sudo ./openremote")
	case errors.Is(err, uinput.ErrUnsupported):
		return i18n.T("virtual gamepad exists only on Linux", "виртуальный геймпад есть только в Linux")
	default:
		return err.Error()
	}
}

func lanIPv4() []string {
	ifaces, err := net.Interfaces()
	if err != nil {
		return nil
	}
	var out []string
	for _, ifi := range ifaces {
		if !phoneIface(ifi) {
			continue
		}
		addrs, err := ifi.Addrs()
		if err != nil {
			continue
		}
		for _, a := range addrs {
			ipnet, ok := a.(*net.IPNet)
			if !ok {
				continue
			}
			ip := ipnet.IP.To4()
			if ip == nil || ip.IsLoopback() || ip.IsLinkLocalUnicast() || ip.IsUnspecified() {
				continue
			}
			out = append(out, ip.String())
		}
	}
	return out
}

// phoneIface keeps addresses a phone on the LAN can actually route to.
// Tunnels and bridge adapters for containers are not that network.
func phoneIface(ifi net.Interface) bool {
	if ifi.Flags&net.FlagUp == 0 || ifi.Flags&net.FlagLoopback != 0 || ifi.Flags&net.FlagPointToPoint != 0 {
		return false
	}
	name := ifi.Name
	switch {
	case strings.HasPrefix(name, "docker"),
		strings.HasPrefix(name, "br-"),
		strings.HasPrefix(name, "veth"),
		strings.HasPrefix(name, "virbr"):
		return false
	default:
		return true
	}
}
