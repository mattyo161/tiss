//usr/bin/env go run "$0" "$@"; exit "$?"

// @description Check TCP port reachability, concurrently, as jsonl
// @usage tiss checkport <host> <port...> [--timeout 3]
// @example tiss checkport db.internal 5432
// @example tiss checkport example.com 80 443 8080 | jq 'select(.open)'
// @needs go
//
// A Go leaf: the first line is a shell/Go polyglot — a valid Go comment
// that, when executed, re-runs the file via `go run`. Ports are dialed
// concurrently, so checking twenty is as fast as checking one.
//
package main

import (
	"fmt"
	"net"
	"os"
	"strconv"
	"sync"
	"time"
)

func main() {
	args := os.Args[1:]
	timeout := 3 * time.Second
	var host string
	var ports []int

	for i := 0; i < len(args); i++ {
		switch a := args[i]; a {
		case "-h", "--help", "help":
			fmt.Fprintln(os.Stderr, "usage: tiss checkport <host> <port...> [--timeout seconds]")
			os.Exit(0)
		case "--timeout":
			i++
			secs, err := strconv.Atoi(args[i])
			if err != nil {
				fmt.Fprintln(os.Stderr, "checkport: --timeout wants whole seconds")
				os.Exit(2)
			}
			timeout = time.Duration(secs) * time.Second
		default:
			if host == "" {
				host = a
			} else if p, err := strconv.Atoi(a); err == nil {
				ports = append(ports, p)
			} else {
				fmt.Fprintf(os.Stderr, "checkport: not a port: %s\n", a)
				os.Exit(2)
			}
		}
	}
	if host == "" || len(ports) == 0 {
		fmt.Fprintln(os.Stderr, "usage: tiss checkport <host> <port...> [--timeout seconds]")
		os.Exit(2)
	}

	type result struct {
		port int
		open bool
		ms   int64
	}
	results := make([]result, len(ports))
	var wg sync.WaitGroup
	for i, p := range ports {
		wg.Add(1)
		go func(i, p int) {
			defer wg.Done()
			start := time.Now()
			conn, err := net.DialTimeout("tcp", net.JoinHostPort(host, strconv.Itoa(p)), timeout)
			ms := time.Since(start).Milliseconds()
			if err == nil {
				conn.Close()
			}
			results[i] = result{port: p, open: err == nil, ms: ms}
		}(i, p)
	}
	wg.Wait()

	status := 0
	for _, r := range results {
		fmt.Printf("{\"host\":%q,\"port\":%d,\"open\":%v,\"ms\":%d}\n", host, r.port, r.open, r.ms)
		if !r.open {
			status = 1
		}
	}
	os.Exit(status)
}
